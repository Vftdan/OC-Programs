local function apiDeliver(api, destination, order)
	local items = require "recipesched.items"
	local recipes = require "recipesched.recipes"

	local destPair = api.getAliases()[destination]
	if not destPair then
		error(("Unknown wired destination: %q"):format(destination))
	end
	for _, entry in ipairs(order) do
		local name = recipes.getRecipeItemName(entry.ref)
		if not name then
			error(("Not an item: %q"):format(entry.ref))
		end
		local specList = items.nameToSpecList(name)
		if #specList == 0 then
			error(("Unpopulated item %q"):format(name))
		end
		-- TODO accept enough information to handle #specList > 1
		local specifications = {
			name = specList[1].name,
			damage = specList[1].damage,
		}
		api.extract(specifications, entry.amount, destPair[1], destPair[2])
	end
end

return require("recipesched.basehostdriver").create({
	features = {delivery = true},
	fallbackFeatures = {stockCount = false --[[TODO]]},
}, function(hostName)
	local rpc = require "rpc"

	local streamPort = 15
	do
		local portStart = hostName:find(":%d+$")
		if portStart then
			streamPort = assert(tonumber(hostName:sub(portStart + 1)))
			hostName = hostName:sub(1, portStart - 1)
		end
	end

	local api = assert(rpc.proxy(hostName, "inv_"), ("Could not create RPC proxy for %q"):format(hostName))

	local function deliver(destination, order)
		return apiDeliver(api, destination, order)
	end

	return {
		deliver = deliver,
	}
end)
