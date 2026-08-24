local lazytable = require "recipesched.lazytable"

local function create(metadata, constr)
	local features = metadata.features or {}
	local fallbackFeatures = metadata.fallbackFeatures or {}

	local getForHost
	getForHost = lazytable.create(constr, {
		iterable = true,
		call = function(hostName)
			return getForHost[hostName]
		end,
	})

	return {
		getForHost = getForHost,
		features = features,
		fallbackFeatures = fallbackFeatures,
	}
end

return {
	create = create,
}
