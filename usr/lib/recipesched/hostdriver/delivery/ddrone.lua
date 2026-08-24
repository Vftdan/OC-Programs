local function apiDeliver(api, destination, order)
	local items = require "recipesched.items"
	local recipes = require "recipesched.recipes"

	local apiOrder = {}
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
			maxSize = specList[1].maxSize,
			count = entry.amount,
		}
		table.insert(apiOrder, specifications)
	end
	api.deliver(destination, apiOrder)
end

return require("recipesched.basehostdriver").create({
	features = {delivery = true},
}, function(hostName)
	local rpc = require "rpc"

	local api = assert(rpc.proxy(hostName, "ddrone_"), ("Could not create RPC proxy for %q"):format(hostName))

	local function deliver(destination, order)
		return apiDeliver(api, destination, order)
	end

	return {
		deliver = deliver,
	}
end)
