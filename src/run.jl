
getVal(::Val{T}) where {T} = T
getVal(x) = x

export new_run, update_config!, finish!

function new_run(
    project::String,
    entity::String,
    session::Session;
    state::Union{Val{:running},Val{:pending}}=Val(:running),
    offline_config::Union{OfflineConfig,Nothing}=nothing,
)
    url = session.host * "/graphql"
    state_str = string(getVal(state))
    run_name = String(rand(ALPHABET, 8))

    mutation = _construct_new_run_mutation()

    variables = Dict(
        "entity" => entity,
        "project" => project,
        "name" => run_name,
        "state" => state_str
    )
    payload = Dict("query" => mutation, "variables" => variables)
    body = JSON3.write(payload)

    auth_header = "Basic " * base64encode("api:$(session.api_key)")
    headers = [
        "Content-Type" => "application/json",
        "Authorization" => auth_header
    ]

    try
        response = HTTP.post(url, headers, body)
        data = JSON3.read(response.body)

        if haskey(data, :errors)
            error("GraphQL Error: ", data.errors)
        end

        result = data.data.upsertBucket
        bucket = result.bucket

        run_id = bucket.id

        run = Run(run_id, run_name, project, entity, OnlineQueue(), offline_config)

        if offline_config === nothing
            start_online_uploader(run, session)
        end

        # Start background upload task if offline mode is enabled and auto_upload is true
        if offline_config !== nothing && offline_config.auto_upload
            start_background_uploader(run, session)
        end

        return run
    catch e
        throw(ErrorException("Failed to create new run: $(e)"))
    end
end

function update_config!(run::Run, session::Session; kwargs...)
    url = "https://api.wandb.ai/graphql"

    formatted_config = Dict(
        k => Dict("value" => v, "desc" => nothing) for (k, v) in kwargs
    )

    mutation = _construct_update_config_mutation()
    variables = Dict(
        "id" => run.id,
        "config" => JSON3.write(formatted_config)
    )
    payload = Dict("query" => mutation, "variables" => variables)
    body = JSON3.write(payload)

    auth_header = "Basic " * base64encode("api:$(session.api_key)")
    headers = [
        "Content-Type" => "application/json",
        "Authorization" => auth_header
    ]

    try
        response = HTTP.post(url, headers, body)
        data = JSON3.read(response.body)

        if haskey(data, :errors)
            error("GraphQL Error: ", data.errors)
        end

        return
    catch e
        throw(ErrorException("Failed to update config for run $(run.id): $e"))
    end

end


function finish!(run::Run, session::Session; exit_code::Int=0)
    # Flush any remaining queued data
    try
        flush_batch!(run, session)
    catch e
        @warn "Failed to flush remaining queued data: $e"
    end

    # Stop background uploaders if running
    stop_online_uploader(run)
    stop_background_uploader(run)

    url = "https://api.wandb.ai/files/$(run.entity)/$(run.project)/$(run.name)/file_stream"

    payload = Dict(
        "exitcode" => exit_code,
        "complete" => true
    )

    body = JSON3.write(payload)
    auth_header = "Basic " * base64encode("api:$(session.api_key)")
    headers = [
        "Content-Type" => "application/json",
        "Authorization" => auth_header
    ]

    try
        HTTP.post(url, headers, body)
    catch e
        throw(ArgumentError("Failed to signal run completion for $(run.id): $e"))
    end
end
