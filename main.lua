local SCRIPT_CLASSES = {LocalScript = true, Script = true, ModuleScript = true}
local REMOTE_CLASSES = {RemoteEvent = true, RemoteFunction = true, BindableEvent = true, BindableFunction = true}
local REMOTE_METHODS = {RemoteFunction = "InvokeServer", BindableEvent = "Fire", BindableFunction = "Invoke"}
local SERVICE_SCAN_ORDER = {"ReplicatedFirst", "ReplicatedStorage", "Players", "StarterPlayer"}
local README_TEXT =
    [[# READ THIS FILE

Read and understand the primary files inside these folders to map out the game’s structure.

Each file includes metadata at the top describing its contents. That metadata lists the true Roblox path (e.g., `-- Path: game:GetService("ReplicatedStorage").path.to.file`) and, when applicable, provides a ready-to-use accessor line (`-- require(...)` for ModuleScripts, `-- getsenv(...)` for LocalScripts). When interacting with exports, follow those metadata instructions rather than the physical folder layout.

Every file contains decompiled Lua from a game. It will not be perfect, but it should provide enough insight into how the game functions. Do not edit these exports—they are read-only references meant to help you build external scripts.

## Folder Overview
- `ReplicatedFirst/` – Initialization scripts that run before the default loading finishes.
- `ReplicatedStorage/` – Shared modules, remotes, and configuration objects accessible to both client and server.
- `Players/` – Player-specific LocalScripts (e.g., inside `PlayerScripts`).
- `StarterPlayer/` – Templates for character scripts (`StarterCharacterScripts`, `StarterPlayerScripts`) that replicate to each client.

## Metadata Legend
- `require(...)` / `getsenv(...)` – Copy/paste-friendly lines showing how to reference the script in Roblox; if neither applies, the metadata falls back to the raw path.
- `ClassName` – Script type (ModuleScript, LocalScript, etc.) for quick filtering.
- `Service` – Top-level service (ReplicatedStorage, Players, etc.) to help you scope systems quickly.
- `Children` – Count of direct descendants harvested under that script, signaling how deep its hierarchy runs.

## Server
- Do not worry about the server at all. Act as if we have zero information about it—we are just random exploiters using an executor.
]]

local folders, checked, counts, names = {}, {}, {}, {}

local function state()
    folders, checked, counts, names = {}, {}, {}, {}
end

local function ensure(path)
    if not folders[path] then
        makefolder(path)
        folders[path] = true
    end
end

local function record(path, instance)
    local cached = names[instance]
    if cached then
        return cached
    end

    local scope = counts[path]
    if not scope then
        scope = {}
        counts[path] = scope
    end

    local name = instance.Name:gsub('[<>:"/\\|%?%*]', "_")
    scope[name] = (scope[name] or 0) + 1
    if scope[name] > 1 then
        name = name .. scope[name]
    end

    names[instance] = name
    return name
end

local function script(instance, path, fileName, childCount)
    local source = instance.Source

    if (not source or source == "") and decompile then
        source = decompile(instance)
    end

    if not source or source == "" then
        return
    end

    local parts = instance:GetFullName():split(".")
    for index = 2, #parts do
        parts[index] = "." .. parts[index]
    end

    local rootPath = 'game:GetService("' .. parts[1] .. '")' .. table.concat(parts, "", 2)
    local accessor =
        instance.ClassName == "ModuleScript" and "-- Path: require(" .. rootPath .. ")" or
        (instance.ClassName == "LocalScript" and "-- Path: getsenv(" .. rootPath .. ")") or
        "-- Path: " .. rootPath

    local header = {
        accessor,
        "-- ",
        "-- Service: " .. parts[1],
        (childCount and childCount > 0) and "-- Children: " .. childCount or nil,
        "-- ClassName: " .. instance.ClassName
    }

    local filtered = {}
    for _, line in ipairs(header) do
        if line then
            table.insert(filtered, line)
        end
    end

    ensure(path)
    writefile(path .. fileName .. ".lua", table.concat(filtered, "\n") .. "\n\n" .. source)
end

local function remote(instance, path, fileName)
    local parts = instance:GetFullName():split(".")
    for index = 2, #parts do
        parts[index] = ':WaitForChild("' .. parts[index] .. '")'
    end

    local header = {
        "-- " .. 'game:GetService("' .. parts[1] .. '")' .. table.concat(parts, "", 2),
        "-- ",
        "-- ClassName: " .. instance.ClassName,
        "-- Method: " .. (REMOTE_METHODS[instance.ClassName] or "FireServer")
    }

    ensure(path)
    writefile(
        path .. fileName .. ".remote",
        table.concat(header, "\n") ..
            "\n\n" ..
                'game:GetService("' ..
                    parts[1] ..
                        '")' ..
                            table.concat(parts, "", 2) ..
                                ":" .. (REMOTE_METHODS[instance.ClassName] or "FireServer") .. "()"
    )
end

local function log(basePath)
    local logRoot = basePath .. "logged/"
    ensure(logRoot)

    local function dump(filename, fetcher)
        local items = fetcher()
        local lines = {"(unavailable)"}

        if items and #items > 0 then
            table.sort(items)
            lines = items
        end

        writefile(logRoot .. filename, table.concat(lines, "\n"))
    end

    dump(
        "loaded_modules.txt",
        function()
            if typeof(getloadedmodules) ~= "function" then
                return
            end

            local entries = {}
            for _, module in ipairs(getloadedmodules()) do
                if module then
                    table.insert(entries, module:GetFullName())
                end
            end
            return entries
        end
    )

    dump(
        "running_scripts.txt",
        function()
            if typeof(getrunningscripts) ~= "function" then
                return
            end

            local entries = {}
            for _, script in ipairs(getrunningscripts()) do
                if script then
                    table.insert(entries, script:GetFullName())
                end
            end
            return entries
        end
    )
end

local function walk(instance, path)
    if checked[instance] then
        return
    end

    checked[instance] = true
    local fileName = record(path, instance)
    local children = instance:GetChildren()

    if SCRIPT_CLASSES[instance.ClassName] then
        script(instance, path, fileName, #children)
        if #children > 0 then
            local childPath = path .. fileName .. " children/"
            ensure(childPath)
            for _, child in ipairs(children) do
                walk(child, childPath)
            end
        end
        return
    end

    if REMOTE_CLASSES[instance.ClassName] then
        remote(instance, path, fileName)
        if #children > 0 then
            local childPath = path .. fileName .. " children/"
            ensure(childPath)
            for _, child in ipairs(children) do
                walk(child, childPath)
            end
        end
        return
    end

    for _, child in ipairs(children) do
        walk(child, path)
    end
end

local function run()
    state()

    local product = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    local basePath = product:gsub("[^%w%s%-]", ""):gsub("%s+", " "):gsub("%s+$", "") .. "@harvest/"

    if isfolder(basePath) then
        delfolder(basePath)
    end

    makefolder(basePath)
    writefile(basePath .. "README.md", README_TEXT)
    log(basePath)

    for _, serviceName in ipairs(SERVICE_SCAN_ORDER) do
        local service = game:GetService(serviceName)
        if service then
            local root = basePath .. serviceName .. "/"
            ensure(root)
            for _, child in ipairs(service:GetChildren()) do
                walk(child, root)
            end
        end
    end
end

local startTime = tick()
run()
print("harvest finished in " .. string.format("%.2f", tick() - startTime) .. " seconds")
 
