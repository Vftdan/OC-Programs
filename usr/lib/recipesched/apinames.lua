local apinames = {}

local function addToApi(module, method)
	apinames[module .. "_" .. method] = {module, method}
end

local function addAllToApi(module, methods)
	for _, method in ipairs(methods) do
		addToApi(module, method)
	end
end

addAllToApi("items", {
	"reload",
	"getRegistryElement",
	"getRegistryKeys",
})

addAllToApi("recipes", {
	"reload",
	"getRegistryElement",
	"getRegistryKeys",
})

addAllToApi("planner", {
	"planForItem",
})

addAllToApi("executor", {
	"registerJobFromPlan",
	"getJobInfo",
	"getJobList",
	"killJob",
})

return apinames
