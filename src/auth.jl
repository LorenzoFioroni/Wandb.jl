
export login, logout

function _check_api_key(
    key::String
)::Union{String,Nothing}
    key == "" && return "API key is empty."
    !occursin(r"^[A-Za-z0-9_]+$", key) && return "API key may only contain letters A-Z, digits and underscores."
    length(key) < 40 && return "API key must have 40+ characters, has $(length(key))."
    return nothing
end

function _get_netrc_file_path()
    # Use the NETRC environment variable if it is set, otherwise use the default location
    (netrc_file = get(ENV, "NETRC", nothing)) !== nothing && return expanduser(netrc_file)

    if Sys.iswindows()
        return joinpath(homedir(), "_netrc")
    else
        return joinpath(homedir(), ".netrc")
    end
end

function _update_netrc(
    path::String,
    machine::String,
    password::String;
    remove::Bool=false
)
    uri = URIs.URI(machine)
    machine = isnothing(uri.host) ? machine : uri.host
    machine_line = "machine $machine"
    lines = isfile(path) ? readlines(path) : String[]
    machine_index = findfirst(occursin(machine_line), lines)
    if isnothing(machine_index)
        remove && return

        # Add new entry
        push!(lines, machine_line)
        push!(lines, "  login user")
        push!(lines, "  password $password")
    elseif remove
        # Remove existing entry
        deleteat!(lines, machine_index:machine_index+2)
    else
        # Update existing entry
        lines[machine_index+1] = "  login user"
        lines[machine_index+2] = "  password $password"
    end
    write(path, join(lines, "\n") * "\n")
end

function api_to_app_url(api_url::AbstractString)::String
    if occursin("://api.wandb.test", api_url)
        # dev mode
        return strip(replace(api_url, "://api." => "://app."), '/')
    elseif occursin("://api.wandb.", api_url)
        # cloud
        return strip(replace(api_url, "://api." => "://"), '/')
    elseif occursin("://api.", api_url)
        # onprem cloud
        return strip(replace(api_url, "://api." => "://app."), '/')
    end
    # wandb/local
    return api_url
end

function authorize_url(host)::String
    app_url = api_to_app_url(host)
    uri = URI(app_url)

    scheme = isnothing(uri.scheme) ? "https" : uri.scheme

    result = URI(
        scheme=scheme,
        host=uri.host,
        port=uri.port,
        path="/authorize",
    )

    return string(result)
end

function _get_netrc(path::String, host::String)
    if !isfile(path)
        return nothing
    end
    lines = readlines(path)
    uri = URIs.URI(host)
    machine = isnothing(uri.host) ? host : uri.host
    machine_line = "machine $machine"
    machine_index = findfirst(occursin(machine_line), lines)
    if machine_index === nothing
        return nothing
    end
    if machine_index + 2 > length(lines)
        return nothing
    end
    login_line = lines[machine_index+1]
    password_line = lines[machine_index+2]
    login = strip(split(login_line)[end])
    password = strip(split(password_line)[end])
    return (login=login, password=password)
end

function login(
    host::String="https://api.wandb.ai"
)
    auth = _get_netrc(_get_netrc_file_path(), host)
    if auth !== nothing
        println("Already logged in to Weights & Biases at $host")
        println("Username: $(auth.login)")
        println("Run `wandb.logout()` to log out.")
        return Session(String(auth.password); host=host)
    end

    auth_url = authorize_url(host)
    println("Logging in to Weights & Biases at $host")
    println("Create a new API key at $auth_url and paste it here.")
    print("API Key: ")
    api_key = readline()

    check = _check_api_key(api_key)
    if !isnothing(check)
        throw(ArgumentError("Invalid API key: $check"))
    end

    # Save the API key to the .netrc file
    _update_netrc(_get_netrc_file_path(), host, api_key)
    return Session(api_key; host=host)
end

function logout(
    host::String="https://api.wandb.ai"
)
    path = _get_netrc_file_path()
    auth = _get_netrc(path, host)
    if auth === nothing
        println("Not logged in to Weights & Biases at $host")
        println("Run `wandb.login()` to log in.")
        return
    end
    println("Logging out of Weights & Biases at $host")
    _update_netrc(path, host, "", remove=true)

end
