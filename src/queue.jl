
export get_queue_length, set_min_request_interval!, set_online_flush_interval!, set_max_batch_size!

function add_to_queue!(queue::OnlineQueue, entry::Dict{String,<:Any})
    lock(queue.lock) do
        push!(queue.data, entry)
    end
end

function should_flush_queue(queue::OnlineQueue)::Bool
    lock(queue.lock) do
        return !isempty(queue.data) && (time() - queue.last_upload_time) >= queue.min_interval
    end
end

function peek_queue(queue::OnlineQueue, max_items::Int)::Vector{Dict{String,Any}}
    lock(queue.lock) do
        if max_items <= 0
            return Dict{String,Any}[]
        end
        return copy(view(queue.data, 1:min(length(queue.data), max_items)))
    end
end

function clear_queue!(queue::OnlineQueue)
    lock(queue.lock) do
        queue.data = Dict{String,Any}[]
        queue.last_upload_time = time()
    end
end

function remove_queue_prefix!(queue::OnlineQueue, count::Int)
    lock(queue.lock) do
        if count <= 0
            return
        end
        if count >= length(queue.data)
            queue.data = Dict{String,Any}[]
        else
            queue.data = queue.data[count+1:end]
        end
        queue.last_upload_time = time()
    end
end

function advance_upload_offset!(queue::OnlineQueue, count::Int)
    lock(queue.lock) do
        if count > 0
            queue.uploaded_offset += count
        end
    end
end

function queue_length(queue::OnlineQueue)::Int
    lock(queue.lock) do
        return length(queue.data)
    end
end

"""Get the current number of items in the queue."""
function get_queue_length(run::Run)::Int
    return queue_length(run.queue)
end

"""Set the minimum time (seconds) between requests in online mode."""
function set_min_request_interval!(run::Run, min_interval::Float64)
    if min_interval < 0
        throw(ArgumentError("min_interval must be non-negative"))
    end
    run.queue.min_interval = min_interval
end

"""Set the background check interval (seconds) in online mode."""
function set_online_flush_interval!(run::Run, flush_interval::Float64)
    if flush_interval <= 0
        throw(ArgumentError("flush_interval must be positive"))
    end
    run.queue.flush_interval = flush_interval
end

"""Set the maximum number of log entries per upload in online mode."""
function set_max_batch_size!(run::Run, max_batch_size::Int)
    if max_batch_size <= 0
        throw(ArgumentError("max_batch_size must be positive"))
    end
    run.queue.max_batch_size = max_batch_size
end
