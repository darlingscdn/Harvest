local SCRIPT_CLASSES = {
	LocalScript = true,
	Script = true,
	ModuleScript = true
}
local REMOTE_CLASSES = {
	RemoteEvent = true,
	RemoteFunction = true,
	BindableEvent = true,
	BindableFunction = true
}
local REMOTE_METHODS = {
	RemoteFunction = "InvokeServer",
	BindableEvent = "Fire",
	BindableFunction = "Invoke"
}
local SERVICES = {
	"ReplicatedFirst",
	"ReplicatedStorage",
	"Players",
	"StarterPlayer"
}
local AGENTS = [[
## Overview
This repo contains decompiled lua scripts.

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

Path: Full instance path.
Service: Top-level service.
ClassName: Instance type (ModuleScript, LocalScript, Script, etc.).
Children: Number of direct children.

Always use the metadata for referencing scripts instead of relying on folder structure.

---

## Remotes

Remote instances:
- Full access path using `WaitForChild`
- Correct invocation method:

RemoteEvent -> FireServer
RemoteFunction -> InvokeServer
BindableEvent -> Fire
BindableFunction -> Invoke

---

## Notes

These files are for analysis only and should not be modified.

They can be used to:
- Understand game structure
- Develop external scripts

---

## Server

No server-side information is available.

Assume:
- Only client-side visibility exists
- Server validation is unknown
- Behavior must be inferred from client code
]]

local folders, checked, counts, names = {}, {}, {}, {}

local function check(dir)
	if not folders[dir] then
		makefolder(dir);
		folders[dir] = true
	end
end

local function empty(dir)
	if not isfolder(dir) then
		return
	end
	local ok, files = pcall(listfiles, dir)
	if ok and # files == 0 then
		pcall(delfolder, dir);
		folders[dir] = nil
	end
end

local function clean(name)
	name = tostring(name or ""):gsub('[<>:"/\\|%?%*]', "_"):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.+$", "")
	return name ~= "" and name or "unnamed"
end

local function path(instance, wfc)
	local parts = instance:GetFullName():split(".")
	local out = {
		'game:GetService("' .. parts[1] .. '")'
	}
	for i = 2, # parts do
		out[i] = wfc and ':WaitForChild("' .. parts[i] .. '")' or '.' .. parts[i]
	end
	return out
end

local function getsource(instance)
	local function normalize(s)
		if not s then
			return nil
		end
		s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
		local t = s:match("^%s*(.-)%s*$")
		return (t == "" or t == "-- Empty bytecode") and nil or s
	end
	local s = instance.Source
	if (not s or s == "") and decompile then
		s = decompile(instance)
	end
	return normalize(s)
end

-- rah 
local function uniquebase(product)
	local stem = product:gsub("[^%w%s%-]", ""):gsub("%s+", " "):gsub("%s+$", "")
	stem = (stem == "" and "game" or stem:sub(1, 72)) .. "@harvest"
	local path = stem .. "/"
	if not isfolder(path) then
		return path
	end
	local t, n = os.time(), 1
	repeat
		path = stem .. "_" .. t .. (n > 1 and "_" .. n or "") .. "/";
		n = n + 1
	until not isfolder(path)
	return path
end

local function record(dir, instance)
	if names[instance] then
		return names[instance]
	end
	counts[dir] = counts[dir] or {}
	local name = clean(instance.Name)
	counts[dir][name] = (counts[dir][name] or 0) + 1
	if counts[dir][name] > 1 then
		name = name .. counts[dir][name]
	end
	names[instance] = name
	return name
end

local function script(instance, dir, name, nchildren)
	local source = getsource(instance)
	if not source then
		return
	end
	local parts = path(instance)
	local root = table.concat(parts)
	local cls = instance.ClassName
	local prefix = cls == "ModuleScript" and "require" or cls == "LocalScript" and "getsenv" or nil
	local lines = {
		"-- Path: " .. (prefix and prefix .. "(" .. root .. ")" or root),
		"--",
		"-- Service: " .. parts[1]
	}
	if nchildren > 0 then
		lines[# lines + 1] = "-- Children: " .. nchildren
	end
	lines[# lines + 1] = "-- ClassName: " .. cls
	check(dir)
	writefile(dir .. name .. ".lua", table.concat(lines, "\n") .. "\n\n" .. source)
end

local function remote(instance, dir, name)
	local parts = path(instance, true)
	local root = parts[1] .. table.concat(parts, "", 2)
	local method = REMOTE_METHODS[instance.ClassName] or "FireServer"
	check(dir)
	writefile(dir .. name .. ".remote", ("-- %s\n--\n-- ClassName: %s\n-- Method: %s\n\n%s:%s()"):format(root, instance.ClassName, method, root, method))
end

local function walk(instance, dir)
	if checked[instance] then
		return
	end
	checked[instance] = true
	local name = record(dir, instance)
	local children = instance:GetChildren()
	local cls = instance.ClassName
	if SCRIPT_CLASSES[cls] then
		script(instance, dir, name, # children)
	elseif REMOTE_CLASSES[cls] then
		remote(instance, dir, name)
	else
		for _, child in ipairs(children) do
			walk(child, dir)
		end
		return
	end
	if # children > 0 then
		local sub = dir .. name .. " children/"
		check(sub)
		for _, child in ipairs(children) do
			walk(child, sub)
		end
		empty(sub)
	end
end

local happy, sad = xpcall(function()
	folders, checked, counts, names = {}, {}, {}, {}
	local t0 = tick()
	local product = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
	local base = uniquebase(product)
	makefolder(base)
	writefile(base .. "AGENTS.md", AGENTS)
	for _, svc in ipairs(SERVICES) do
		local service = game:GetService(svc)
		if not service then
			continue
		end
		local root = base .. svc .. "/"
		check(root)
		for _, child in ipairs(service:GetChildren()) do
			walk(child, root)
		end
		empty(root)
	end
	print(("[harvest] %.2fs"):format(tick() - t0))
end, debug.traceback)

if not happy then
	warn("[harvest] \n" .. tostring(sad))
end
