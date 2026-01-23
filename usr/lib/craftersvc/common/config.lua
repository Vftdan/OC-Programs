local serialization = require "serialization"
local os = require "os"
local filesystem = require "filesystem"

local function readConfig(filename, forcetable)
	local f = io.open(filename, "rb")
	if not f then
		return nil
	end
	local result = serialization.unserialize(f:read("*a"))
	f:close()
	if forcetable and type(result) ~= "table" then
		return nil
	end
	return result
end

local function writeConfig(filename, cfg)
	local dir = filename:match("^.*/")
	if dir and not filesystem.exists(dir) then
		os.execute("mkdir -p " .. dir)
	end
	local f, reason = io.open(filename, "wb")
	if not f then
		error("Failed to open for writing (" .. tostring(reason) .. ")")
	end
	f:write(serialization.serialize(cfg))
	f:close()
end

local function get(cfg, path)
	for _, key in ipairs(path) do
		if type(cfg) ~= "table" then
			return nil
		end
		cfg = cfg[key]
	end
	return cfg
end

local function put(cfg, path, value)
	if type(cfg) ~= "table" then
		error("Cannot put into a non-table")
	end
	if #path < 1 then
		error("Cannot put at an empty path")
	end
	local parent = cfg
	local node = parent[path[1]]
	for i = 2, #path do
		if type(node) ~= "table" then
			node = {}
			parent[path[i - 1]] = node
		end
		parent = node
		node = parent[path[i]]
	end
	parent[path[#path]] = value
end

return {
	readConfig = readConfig,
	writeConfig = writeConfig,
	get = get,
	put = put,
}
