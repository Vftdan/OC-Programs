local shell = require "shell"
local util = require "shell-completion.util"
local items = require "recipesched.items"

local function getItemNames()
	local result = {}
	for name in pairs(items.registry) do
		table.insert(result, name)
	end
	table.sort(result)
	return result
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
