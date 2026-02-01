local CFG_DIR = "/etc/recipesched/"

local function makeEnv(opts)
	opts = opts or {}
	imports = opts.imports or {}
	local shouldAssign = opts.shouldAssign
	local mt = {}
	local env = setmetatable({}, mt)
	local shadow = {globals = {}}
	if not shouldAssign then
		function shouldAssign()
			return true
		end
	end
	function mt:__index(k)
		local imported = imports[k]
		if imported ~= nil then
			return imported
		end
		return shadow.globals[k]
	end
	function mt:__newindex(k, v)
		local ok, override = shouldAssign(k, v)
		if ok then
			if override ~= nil then
				v = override
			end
			shadow.globals[k] = v
		end
	end
	function mt:__meta()
		return nil
	end
	return env, shadow
end

local function loads(str, opts)
	opts = opts or {}
	local env, shadow = makeEnv({
		imports = opts.imports,
		shouldAssign = opts.shouldAssign,
	})
	local mode = "t"
	local cb, err = load(str, opts.chunkname, mode, env)
	if not cb then
		error("Config syntax error: " .. err)
	end
	local result = table.pack(xpcall(cb, debug.traceback))
	if not result[1] then
		error("Config runtime error: " .. tostring(result[2]))
	end
	return {
		globals = shadow.globals,
		returns = table.pack(table.unpack(result, 2, result.n)),
	}
end

local function loadNamed(name, opts)
	opts = opts or {}
	local fname = CFG_DIR .. name .. ".cfg"
	local fh = io.open(fname, "r")
	if not fh then
		return nil
	end
	return loads(fh:read("*a"), {
		imports = opts.imports,
		shouldAssign = opts.shouldAssign,
		chunkname = fname,
	})
end

return {
	loads = loads,
	loadNamed = loadNamed,
}
