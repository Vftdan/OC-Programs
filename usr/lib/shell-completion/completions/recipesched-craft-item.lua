local shell = require "shell"
local util = require "shell-completion.util"
local client = require "recipesched.client"

local function getItemNames()
	return client.getApi().items.getRegistryKeys()
end

shell.registerCompletion("recipesched-craft-item", {
	noBuiltin = true,
	populate = function(result, argv)
		if #argv == 2 then
			util.populateMatching(result, argv[#argv], getItemNames())
		elseif #argv == 3 then
			util.populateMatching(result, argv[#argv], {"64"})
		end
	end
})
