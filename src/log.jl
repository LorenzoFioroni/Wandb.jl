
export log, upload_file!, manual_flush!, upload_cached_logs

function log(run::Run, session::Session, data::Dict{String,<:Any})
    current_timestamp = time()

    # Prepare log entry
    log_entry = merge(Dict("_step" => run.offset, "_timestamp" => current_timestamp), data)
    run.offset += 1

    # If offline mode is enabled, write directly to cache file (no queue needed)
    if run.offline_config !== nothing && run.offline_config.enabled
        cache_file = get_offline_cache_file(run.offline_config, run.name)
        open(cache_file, "a") do f
            write(f, JSON3.write(log_entry) * "\n")
        end
        return
    end

    # Online mode: add to queue with rate limiting
    add_to_queue!(run.queue, log_entry)

    # Check if enough time has passed to flush (non-blocking)
    if should_flush_queue(run.queue)
        flush_batch_async!(run, session; max_batches=1)
    end
end

function flush_batch_async!(run::Run, session::Session; max_batches::Int=1)
    """Non-blocking flush - spawns async task for upload."""
    @async flush_batch_impl!(run, session; max_batches=max_batches)
end

function flush_batch!(run::Run, session::Session; max_batches::Int=1)
    """Blocking flush - waits for upload to complete."""
    flush_batch_impl!(run, session; max_batches=max_batches)
end

function flush_batch_impl!(run::Run, session::Session; max_batches::Int=1)
    batches_sent = 0
    while batches_sent < max_batches
        if !should_flush_queue(run.queue)
            return
        end

        batch_data = peek_queue(run.queue, run.queue.max_batch_size)
        if isempty(batch_data)
            return
        end

        # Online mode: send to server
        batch_offset = run.queue.uploaded_offset
        send_batch_to_server(run, session, batch_data; offset=batch_offset)
        advance_upload_offset!(run.queue, length(batch_data))
        remove_queue_prefix!(run.queue, length(batch_data))

        batches_sent += 1

        if batches_sent < max_batches && run.queue.min_interval > 0
            sleep(run.queue.min_interval)
        end
    end
end

function send_batch_to_server(run::Run, session::Session, batch_data::Vector{Dict{String,Any}}; offset::Union{Int,Nothing}=nothing)
    url = "https://api.wandb.ai/files/$(run.entity)/$(run.project)/$(run.name)/file_stream"

    lines = [JSON3.write(entry) for entry in batch_data]

    upload_offset = isnothing(offset) ? (run.offset - length(batch_data)) : offset

    payload = Dict(
        "files" => Dict(
            "wandb-history.jsonl" => Dict(
                "offset" => upload_offset,
                "content" => lines
            )
        ),
        "complete" => false
    )

    body = JSON3.write(payload)

    auth_header = "Basic " * base64encode("api:$(session.api_key)")
    headers = ["Content-Type" => "application/json", "Authorization" => auth_header]

    response = HTTP.post(url, headers, body)
    if response.status != 200
        throw(ErrorException("Failed to send batch to server: HTTP $(response.status)"))
    end
end

function start_online_uploader(run::Run, session::Session)
    if run.queue.upload_task !== nothing
        return
    end

    run.queue.enabled = true

    task = @async begin
        try
            while run.queue.enabled
                sleep(run.queue.flush_interval)
                try
                    if should_flush_queue(run.queue)
                        flush_batch!(run, session; max_batches=typemax(Int))
                    end
                catch e
                    @warn "Online background flush failed for run $(run.id): $e"
                end
            end
        catch e
            @warn "Online uploader task encountered error: $e"
        end
    end

    run.queue.upload_task = task
end

function stop_online_uploader(run::Run)
    if run.queue.upload_task !== nothing
        run.queue.enabled = false
        run.queue.upload_task = nothing
    end
end

function upload_file!(run::Run, session::Session, file_paths::Vector{String})
    url = "https://api.wandb.ai/graphql"

    filenames = basename.(file_paths)

    mutation = _construct_upload_file_mutation()
    variables = Dict(
        "entity" => run.entity,
        "project" => run.project,
        "run" => run.name,
        "files" => filenames
    )
    payload = Dict("query" => mutation, "variables" => variables)
    body = JSON3.write(payload)
    auth_header = "Basic " * base64encode("api:$(session.api_key)")
    headers = ["Content-Type" => "application/json", "Authorization" => auth_header]

    try
        response = HTTP.post(url, headers, body)
        data = JSON3.read(response.body)

        if haskey(data, :errors)
            error("GraphQL Error: ", data.errors)
        end

        result = data.data.createRunFiles.files
        for (file_path, file_info) in zip(file_paths, result)
            upload_url = file_info.uploadUrl
            file_content = read(file_path)
            content_md5 = base64encode(md5(file_content))

            put_headers = [
                "Content-Type" => "application/octet-stream",
                "Content-MD5" => content_md5
            ]
            final_put_url = startswith(upload_url, "/") ? "https://api.wandb.ai" * upload_url : upload_url
            put_response = HTTP.put(final_put_url, put_headers, file_content)

            if put_response.status == 200
                println("Successfully uploaded $(basename(file_path)) to run $(run.id)")
            end
        end
    catch e
        throw(ErrorException("Failed to upload files for run $(run.id): $e"))
    end
end

function start_background_uploader(run::Run, session::Session)
    if run.offline_config === nothing || run.offline_config.upload_task !== nothing
        return
    end

    task = @async begin
        try
            while run.offline_config.enabled
                sleep(run.offline_config.flush_interval)
                try
                    # Upload all cached logs to server
                    upload_cached_logs(run, session)
                catch e
                    @warn "Background upload failed for run $(run.id): $e"
                end
            end
        catch e
            @warn "Background uploader task encountered error: $e"
        end
    end

    run.offline_config.upload_task = task
end

function stop_background_uploader(run::Run)
    if run.offline_config !== nothing && run.offline_config.upload_task !== nothing
        run.offline_config.enabled = false
        # Give the task a moment to finish
        sleep(0.1)
        run.offline_config.enabled = true
    end
end

function manual_flush!(run::Run, session::Session)
    """Manually flush any pending queued logs."""
    flush_batch!(run, session; max_batches=typemax(Int))
end

function upload_cached_logs(run::Run, session::Session)
    """Upload all cached logs from local storage to the server."""
    if run.offline_config === nothing
        throw(ErrorException("Offline mode is not enabled for this run"))
    end

    cache_file = get_offline_cache_file(run.offline_config, run.name)
    if !isfile(cache_file)
        @debug "No cached logs found for run $(run.id)"
        return
    end

    try
        # Read all cached entries
        cached_entries = Dict{String,Any}[]
        open(cache_file, "r") do f
            for line in eachline(f)
                if !isempty(line)
                    parsed = JSON3.read(line)
                    # Convert JSON3.Object with symbol keys to plain Dict with string keys
                    entry = Dict{String, Any}(String(k) => v for (k, v) in parsed)
                    push!(cached_entries, entry)
                end
            end
        end

        if isempty(cached_entries)
            @debug "No cached log entries to upload"
            return
        end

        # Send all cached entries to server
        send_batch_to_server(run, session, cached_entries)

        # Clear the cache file after successful upload
        rm(cache_file, force=true)
        @debug "Successfully uploaded $(length(cached_entries)) cached log entries"
    catch e
        throw(ErrorException("Failed to upload cached logs: $e"))
    end
end
