
# Session configuration
export Session

mutable struct Session
    api_key::String
    host::String
    
    function Session(api_key::String; host::String="https://api.wandb.ai")
        check = _check_api_key(api_key)
        if !isnothing(check)
            throw(ArgumentError("Invalid API key: $check"))
        end
        new(api_key, host)
    end
end

# Queue structure for online mode with rate limiting
mutable struct OnlineQueue
    data::Vector{Dict{String,Any}}
    lock::ReentrantLock
    last_upload_time::Float64  # timestamp of last upload
    min_interval::Float64      # minimum seconds between uploads
    enabled::Bool
    flush_interval::Float64    # seconds between background checks
    upload_task::Union{Task,Nothing}
    max_batch_size::Int
    uploaded_offset::Int

    function OnlineQueue(min_interval::Float64=1.0; flush_interval::Float64=20.0, max_batch_size::Int=200)
        new(Dict{String,Any}[], ReentrantLock(), time(), min_interval, true, flush_interval, nothing, max_batch_size, 0)
    end
end

# Offline configuration and storage
mutable struct OfflineConfig
    enabled::Bool
    cache_dir::String
    flush_interval::Float64  # seconds
    auto_upload::Bool
    upload_task::Union{Task,Nothing}

    function OfflineConfig(cache_dir::String; flush_interval::Float64=30.0, auto_upload::Bool=true)
        # Create cache directory if it doesn't exist
        mkpath(cache_dir)
        new(true, cache_dir, flush_interval, auto_upload, nothing)
    end
end

mutable struct Run
    id::String
    name::String
    project::String
    entity::String
    offset::Int
    queue::OnlineQueue
    offline_config::Union{OfflineConfig,Nothing}
end

function Run(id::String, name::String, project::String, entity::String)
    return Run(id, name, project, entity, 0, OnlineQueue(), nothing)
end

function Run(id::String, name::String, project::String, entity::String, queue::OnlineQueue, offline_config::Union{OfflineConfig,Nothing}=nothing)
    return Run(id, name, project, entity, 0, queue, offline_config)
end
