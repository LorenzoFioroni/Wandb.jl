
export enable_offline_mode!, disable_offline_mode!

function get_offline_cache_file(config::OfflineConfig, run_name::String)::String
    return joinpath(config.cache_dir, "run_$(run_name)_history.jsonl")
end

"""Enable offline mode for a run with caching to local files."""
function enable_offline_mode!(run::Run, cache_dir::String="./wandb_cache";
    flush_interval::Float64=30.0, auto_upload::Bool=true, session::Union{Session,Nothing}=nothing)
    if auto_upload && session === nothing
        @warn "auto_upload=true has no effect without a session; pass `session=<your_session>` to enable background syncing"
    end
    stop_online_uploader(run)
    run.offline_config = OfflineConfig(cache_dir; flush_interval=flush_interval, auto_upload=auto_upload)

    if auto_upload && session !== nothing
        start_background_uploader(run, session)
    end
end

"""Disable offline mode for a run."""
function disable_offline_mode!(run::Run; session::Union{Session,Nothing}=nothing)
    stop_background_uploader(run)
    run.offline_config = nothing
    if session !== nothing
        start_online_uploader(run, session)
    end
end
