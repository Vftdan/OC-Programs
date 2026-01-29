local planner = require "recipesched.planner"
local executor = require "recipesched.executor"

local function main(itemName, amount)
	if not itemName then
		error("No item name provided")
	end
	if amount then
		amount = tonumber(amount)
	end
	local plan = planner.planForItem(itemName, amount)
	if not plan.success then
		print(plan.reason)
		for _, entry in ipairs(plan.missingItems) do
			print(("Missing %q * %d"):format(entry.item, entry.amount))
		end
		return
	end
	local jobId, queuePos = executor.registerJobFromPlan(plan)
	print(("Created job %s, position in queue #%d"):format(jobId, queuePos))
end

main(...)
