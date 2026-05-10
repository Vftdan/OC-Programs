local shell = require "shell"
local util = require "shell-completion.util"
local client = require "recipesched.client"

local function getJobIds()
	return client.getApi().executor.getJobList()
end

shell.registerCompletion("recipesched-jobs", {
	noBuiltin = true,
	populate = function(result, argv)
		if #argv == 2 then
			util.populateMatching(result, argv[#argv], getJobIds())
		elseif #argv == 3 then
			util.populateMatching(result, argv[#argv], {"kill"})
		end
	end
})
