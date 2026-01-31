local recipes = require "recipesched.recipes"
local rpc = require "rpc"
local inv = require "inv"

local DRONE_SERVER = "dronesrv"  -- TODO use a config file

local function deliverDrone(destination, order)
	local apiOrder = {}
	for _, entry in ipairs(order) do
		local name = recipes.getRecipeItemName(entry.ref)
		if not name then
			error(("Not an item: %q"):format(entry.ref))
		end
		local specList = nameToSpecList(name)
		if #specList == 0 then
			error(("Unpopulated item %q"):format(name))
		end
		-- TODO accept enough information to handle #specList > 1
		local specifications = {
			name = specList[1].name,
			damage = specList[1].damage,
			count = entry.amount,
		}
		table.insert(apiOrder, specifications)
	end
	rpc.call(DRONE_SERVER, "ddrone_deliver", destination, apiOrder)
end

local function deliverWired(destination, order)
	local destPair = inv.getAliases()[destination]
	if not destPair then
		error(("Unknown wired destination: %q"):format(destination))
	end
	for _, entry in ipairs(order) do
		local name = recipes.getRecipeItemName(entry.ref)
		if not name then
			error(("Not an item: %q"):format(entry.ref))
		end
		local specList = nameToSpecList(name)
		if #specList == 0 then
			error(("Unpopulated item %q"):format(name))
		end
		-- TODO accept enough information to handle #specList > 1
		local specifications = {
			name = specList[1].name,
			damage = specList[1].damage,
		}
		inv.extract(specifications, entry.amount, destPair[1], destPair[2])
	end
end

return {
	deliverDrone = deliverDrone,
	deliverWired = deliverWired,
}
