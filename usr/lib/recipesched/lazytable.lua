local function create(getter, opts)
	opts = opts or {}
	local mt = {}
	local storage = {}
	local lazy = setmetatable({}, mt)
	function mt:__index(k)
		local saved = storage[k]
		if saved == nil then
			saved = getter(k)
			storage[k] = saved
		end
		return saved
	end
	function mt:__newindex(k, v)
		if opts.frozen then
			error("Trying to modify a frozen lazy table")
		end
		storage[k] = v
	end
	function mt:__len()
		return #storage
	end
	if opts.hideMeta then
		function mt:__metatable()
			return nil
		end
	end
	mt.__tostring = opts.toString
	if opts.iterable then
		local function wrappedNext(_, k)
			return next(storage, k)
		end
		function mt:__pairs()
			 return wrappedNext, self, nil
		end
	end
	if opts.weak then
		mt.__mode = "v"
	end
	return lazy
end

return {
	create = create,
}
