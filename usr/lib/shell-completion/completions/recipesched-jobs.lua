local shell = require "shell"
local util = require "shell-completion.util"
local executor = require "recipesched.executor"

local function getJobIds()
	local result = {}
	for id in pairs(executor.jobRegistry) do
		table.insert(result, id)
	end
	table.sort(result)
	return result
end

shell.registerCompletion("recipesched-jobs", {
	noBuiltin = true,
	populate = function(result, argv)
		if #argv == 2 then
			util.populateMatching(result, argv[#argv], getJobIds())
		end
	end
})
