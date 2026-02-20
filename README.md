# Wandb.jl

A lightweight Julia interface for [Weights & Biases](https://wandb.ai/). Log metrics, save files, and track experiments directly from your Julia code.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/yourusername/Wandb.jl")
```

## Quick Start

Here is a minimal example demonstrating how to start a run, log metrics, and finish.

### 1. Setup

First, ensure you have your W&B API Key ready. You can find it at [wandb.ai/authorize](https://wandb.ai/authorize).

You can log in via the interactive prompt, which saves your credentials to `~/.netrc` and returns a session:

```julia
using Wandb

# Interactive login
session = Wandb.login() 
```

### 2. Basic Example

```julia
using Wandb

# If you are already logged in via CLI or previous Wandb.login(), you can just call login() to get the session
# Or provide an API key directly: Session("YOUR_API_KEY")
session = Wandb.login()

# Start a new run
# Usage: new_run(project_name, entity_name, session)
# entity_name is usually your username or team name
run = new_run("my-awesome-project", "my-username", session)
println("Run started: $(run.name) (ID: $(run.id))")

# Update hyperparameter configuration
update_config!(run, session; 
    learning_rate = 0.01,
    batch_size = 32,
    architecture = "CNN"
)

# Simulate training loop
for epoch in 1:10
    # specific metrics
    loss = 1.0 / epoch + rand() * 0.1
    accuracy = 1.0 - (1.0 / epoch)
    
    # Log metrics to W&B
    Wandb.log(run, session, Dict(
        "epoch" => epoch,
        "loss" => loss,
        "accuracy" => accuracy
    ))
    
    println("Epoch $epoch: Loss = $loss, Accuracy = $accuracy")
end

# Finish the run
finish!(run, session)
```

## Features

- **Authentication**: `login()`, `logout()`
- **Run Management**: `new_run`, `finish!`, `update_config!`
- **Logging**: `log` metrics, `upload_file!` for artifacts.
- **Offline Mode**: 
  - `enable_offline_mode!(run)`: Cache logs locally.
  - `disable_offline_mode!(run)`: Sync to server.
  - `upload_cached_logs(run, session)`: Upload pending logs.

## Offline Mode

Useful for training on machines with intermittent internet access.

### Basic Offline Mode (Manual Sync)
```julia
# Enable offline mode - logs are saved to ./wandb_cache/
enable_offline_mode!(run)

# Log as usual (fast, no network requests)
Wandb.log(run, session, Dict("val" => 1))

# Later, when online:
upload_cached_logs(run, session)
```

### Offline Mode with Auto-Sync
If you have internet access but want to use the offline buffer for resilience, you can enable auto-sync. This will upload cached logs in the background every `flush_interval` seconds.

```julia
# Enable offline mode with background syncing (e.g., every 10 seconds)
enable_offline_mode!(run; session=session, flush_interval=10.0)
```
