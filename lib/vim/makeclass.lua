local function makeClass(cls)
	cls._MT = {__index = cls}
	cls.new = function(...)
		local obj = setmetatable({}, cls._MT)
		obj:init(...)
		return obj
	end
	return setmetatable(cls, {
		__call = function(cls, ...)
			return cls.new(...)
		end,
	})
end

return makeClass
