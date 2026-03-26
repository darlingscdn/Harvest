local SCRIPT_CLASSES =
    { LocalScript = true, Script = true, ModuleScript = true }
local REMOTE_CLASSES = {
    RemoteEvent = true,
    RemoteFunction = true,
    BindableEvent = true,
    BindableFunction = true,
}
local REMOTE_METHODS = {
    RemoteFunction = "InvokeServer",
    BindableEvent = "Fire",
    BindableFunction = "Invoke",
}
local SERVICE_SCAN_ORDER =
    { "ReplicatedFirst", "ReplicatedStorage", "Players", "StarterPlayer" }
local AGENTS_TEXT = [[
# README

## Overview
This repository contains extracted (decompiled) Lua scripts from a Roblox game. These files are read-only references intended to help analyze the game's structure and behavior.

Each file includes metadata at the top describing:
- The original Roblox path
- How to access it programmatically (e.g., require(...), getsenv(...))
- Its ClassName, Service, and child hierarchy

Decompiled code may be imperfect but should provide enough information for analysis.

---

## Folder Structure

ReplicatedFirst/
Initialization scripts that run before the default loading process completes.

ReplicatedStorage/
Shared modules, remotes, and configuration objects accessible to both client and server.

Players/
Player-specific scripts, typically LocalScripts under PlayerScripts.

StarterPlayer/
Templates for scripts that replicate to each client, including StarterPlayerScripts and StarterCharacterScripts.

---

## Metadata

Each script includes a header with:

Path
The full Roblox path using game:GetService(...). May include:
- require(...) for ModuleScripts
- getsenv(...) for LocalScripts

Service
The top-level service containing the script.

ClassName
The type of instance (ModuleScript, LocalScript, Script, etc.).

Children
The number of direct child instances.

Always use the metadata for referencing scripts instead of relying on folder structure.

---

## Remotes

Remote instances are exported with:
- A full access path using WaitForChild
- The correct invocation method:

RemoteEvent -> FireServer  
RemoteFunction -> InvokeServer  
BindableEvent -> Fire  
BindableFunction -> Invoke 

---

## Usage Notes

These files are for analysis only and should not be modified.

They can be used to:
- Understand system structure
- Identify remotes and modules
- Dvelopment external scripts

---

## Server Assumptions

No server-side information is available.

Assume:
- Only client-side visibility exists
- Server validation is unknown
- Behavior must be inferred from client code

---

## Limitations

Decompiled code may be incomplete, obfuscated, or inaccurate.

Despite this, it remains useful for understanding structure, flow, and potential interaction points.
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

    local rootPath = 'game:GetService("'
        .. parts[1]
        .. '")'
        .. table.concat(parts, "", 2)
    local accessor = instance.ClassName == "ModuleScript"
            and "-- Path: require(" .. rootPath .. ")"
        or (instance.ClassName == "LocalScript" and "-- Path: getsenv(" .. rootPath .. ")")
        or "-- Path: " .. rootPath

    local header = {
        accessor,
        "-- ",
        "-- Service: " .. parts[1],
        (childCount and childCount > 0) and "-- Children: " .. childCount
            or nil,
        "-- ClassName: " .. instance.ClassName,
    }

    local filtered = {}
    for _, line in ipairs(header) do
        if line then
            table.insert(filtered, line)
        end
    end

    ensure(path)
    writefile(
        path .. fileName .. ".lua",
        table.concat(filtered, "\n") .. "\n\n" .. source
    )
end

local function remote(instance, path, fileName)
    local parts = instance:GetFullName():split(".")
    for index = 2, #parts do
        parts[index] = ':WaitForChild("' .. parts[index] .. '")'
    end

    local header = {
        "-- " .. 'game:GetService("' .. parts[1] .. '")' .. table.concat(
            parts,
            "",
            2
        ),
        "-- ",
        "-- ClassName: " .. instance.ClassName,
        "-- Method: " .. (REMOTE_METHODS[instance.ClassName] or "FireServer"),
    }

    ensure(path)
    writefile(
        path .. fileName .. ".remote",
        table.concat(header, "\n")
            .. "\n\n"
            .. 'game:GetService("'
            .. parts[1]
            .. '")'
            .. table.concat(parts, "", 2)
            .. ":"
            .. (REMOTE_METHODS[instance.ClassName] or "FireServer")
            .. "()"
    )
end

local function log(basePath)
    local logRoot = basePath .. "logged/"
    ensure(logRoot)

    local function dump(filename, fetcher)
        local items = fetcher()
        local lines = { "(unavailable)" }

        if items and #items > 0 then
            table.sort(items)
            lines = items
        end

        writefile(logRoot .. filename, table.concat(lines, "\n"))
    end

    dump("loaded_modules.txt", function()
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
    end)

    dump("running_scripts.txt", function()
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
    end)
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

    local product = game:GetService("MarketplaceService")
        :GetProductInfo(game.PlaceId).Name
    local basePath = product
        :gsub("[^%w%s%-]", "")
        :gsub("%s+", " ")
        :gsub("%s+$", "") .. "@harvest/"

    if isfolder(basePath) then
        delfolder(basePath)
    end

    makefolder(basePath)
    writefile(basePath .. "AGENTS.md", AGENTS_TEXT)
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
print(
    "harvest finished in "
        .. string.format("%.2f", tick() - startTime)
        .. " seconds"
)
