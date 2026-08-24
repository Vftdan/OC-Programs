local function getDriverNamesWithFeature(feature, driverNames)
	local result = {}
	local fallbackResult = {}
	for _, driverName in ipairs(driverNames) do
		local factory = require ("recipesched.hostdriver." .. driverName)
		if factory.features[feature] then
			table.insert(result, driverName)
		elseif factory.fallbackFeatures[feature] then
			table.insert(fallbackResult, driverName)
		end
	end
	if #result > 0 then
		return result
	else
		return fallbackResult
	end
end

return {
	hasAllFeatures = function(driverName, featureList)
		local factory = require ("recipesched.hostdriver." .. driverName)
		local primarySet = factory.features
		local fallbackSet = factory.fallbackFeatures
		for _, feature in ipairs(featureList) do
			if not primarySet[feature] and not fallbackSet[feature] then
				return false
			end
		end
		return true
	end,
	loadForHost = function(driverName, hostName)
		local factory = require ("recipesched.hostdriver." .. driverName)
		return factory.getForHost(hostName)
	end,
	togetherHaveAllFeatures = function(featureList, driverNames)
		local remainingFeatures = {}
		for _, feature in ipairs(featureList) do
			remainingFeatures[feature] = true
		end
		for _, driverName in ipairs(driverNames) do
			if not next(remainingFeatures) then
				break
			end
			local factory = require ("recipesched.hostdriver." .. driverName)
			for feature in pairs(factory.features) do
				remainingFeatures[feature] = nil
			end
			for feature in pairs(factory.fallbackFeatures) do
				remainingFeatures[feature] = nil
			end
		end
		if next(remainingFeatures) then
			return false
		end
		return true
	end,
	getDriverNamesWithFeature = getDriverNamesWithFeature,
	getFactoriesWithFeature = function(feature, driverNames)
		local matchedNames = getDriverNamesWithFeature(feature, driverNames)
		local result = {}
		for i, driverName in ipairs(matchedNames) do
			result[i] = require ("recipesched.hostdriver." .. driverName)
		end
		return result
	end,
}
