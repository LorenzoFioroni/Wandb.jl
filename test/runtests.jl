using Test
using Wandb

# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------

@testset "API key validation" begin
    # Valid key (40+ alphanumeric chars)
    valid_key = repeat("a", 40)
    @test isnothing(Wandb._check_api_key(valid_key))

    # Too short
    short_key = repeat("a", 39)
    @test !isnothing(Wandb._check_api_key(short_key))

    # Empty
    @test !isnothing(Wandb._check_api_key(""))

    # Invalid characters
    bad_key = repeat("a", 39) * "!"
    @test !isnothing(Wandb._check_api_key(bad_key))
end

@testset "netrc read/write round-trip" begin
    tmp = tempname()
    host = "https://api.wandb.ai"
    password = repeat("x", 40)

    # Write an entry to a fresh file
    Wandb._update_netrc(tmp, host, password)
    result = Wandb._get_netrc(tmp, host)
    @test result !== nothing
    @test result.password == password
    @test result.login == "user"

    # Update the password
    new_password = repeat("y", 40)
    Wandb._update_netrc(tmp, host, new_password)
    result2 = Wandb._get_netrc(tmp, host)
    @test result2.password == new_password

    # Remove the entry
    Wandb._update_netrc(tmp, host, ""; remove=true)
    @test Wandb._get_netrc(tmp, host) === nothing

    rm(tmp; force=true)
end

@testset "netrc missing file is handled" begin
    tmp = tempname()  # guaranteed to not exist
    rm(tmp; force=true)
    @test Wandb._get_netrc(tmp, "https://api.wandb.ai") === nothing

    # Writing to a non-existent file should create it
    password = repeat("z", 40)
    Wandb._update_netrc(tmp, "https://api.wandb.ai", password)
    @test isfile(tmp)
    result = Wandb._get_netrc(tmp, "https://api.wandb.ai")
    @test result !== nothing
    @test result.password == password

    rm(tmp; force=true)
end

@testset "authorize_url" begin
    url = Wandb.authorize_url("https://api.wandb.ai")
    @test occursin("/authorize", url)
    @test occursin("wandb.ai", url)
end

# ---------------------------------------------------------------------------
# Queue
# ---------------------------------------------------------------------------

@testset "OnlineQueue basic operations" begin
    q = Wandb.OnlineQueue(0.0)  # min_interval=0 so we can flush immediately

    @test Wandb.queue_length(q) == 0
    @test !Wandb.should_flush_queue(q)

    entry = Dict{String,Any}("loss" => 0.5)
    Wandb.add_to_queue!(q, entry)
    @test Wandb.queue_length(q) == 1
    @test Wandb.should_flush_queue(q)

    peeked = Wandb.peek_queue(q, 10)
    @test length(peeked) == 1
    @test peeked[1]["loss"] == 0.5
    # peek should not remove items
    @test Wandb.queue_length(q) == 1

    Wandb.advance_upload_offset!(q, 1)
    @test q.uploaded_offset == 1

    Wandb.remove_queue_prefix!(q, 1)
    @test Wandb.queue_length(q) == 0

    Wandb.clear_queue!(q)
    @test Wandb.queue_length(q) == 0
end

@testset "set_min_request_interval! validation" begin
    run = Wandb.Run("id", "name", "proj", "entity")
    @test_throws ArgumentError Wandb.set_min_request_interval!(run, -1.0)
    Wandb.set_min_request_interval!(run, 0.0)
    @test run.queue.min_interval == 0.0
end

@testset "set_online_flush_interval! validation" begin
    run = Wandb.Run("id", "name", "proj", "entity")
    @test_throws ArgumentError Wandb.set_online_flush_interval!(run, 0.0)
    Wandb.set_online_flush_interval!(run, 5.0)
    @test run.queue.flush_interval == 5.0
end

@testset "set_max_batch_size! validation" begin
    run = Wandb.Run("id", "name", "proj", "entity")
    @test_throws ArgumentError Wandb.set_max_batch_size!(run, 0)
    Wandb.set_max_batch_size!(run, 50)
    @test run.queue.max_batch_size == 50
end

# ---------------------------------------------------------------------------
# Offline mode
# ---------------------------------------------------------------------------

@testset "enable/disable offline mode" begin
    run = Wandb.Run("id", "name", "proj", "entity")
    @test run.offline_config === nothing

    cache_dir = mktempdir()
    Wandb.enable_offline_mode!(run, cache_dir; auto_upload=false)
    @test run.offline_config !== nothing
    @test run.offline_config.enabled
    @test isdir(cache_dir)

    Wandb.disable_offline_mode!(run)
    @test run.offline_config === nothing

    rm(cache_dir; recursive=true, force=true)
end

@testset "offline cache file path" begin
    cfg = Wandb.OfflineConfig(mktempdir())
    path = Wandb.get_offline_cache_file(cfg, "myrun")
    @test endswith(path, "run_myrun_history.jsonl")
    rm(cfg.cache_dir; recursive=true, force=true)
end
