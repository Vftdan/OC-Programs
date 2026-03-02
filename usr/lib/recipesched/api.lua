local apinames = require "recipesched.apinames"
local api = {}

for name, desc in pairs(apinames) do
	local module, method = desc[1], desc[2]
	api[name] = function(...)
		return require("recipesched." .. module)[method](...)
	end
end

return api
