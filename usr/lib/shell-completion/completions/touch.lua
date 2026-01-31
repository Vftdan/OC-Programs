local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "c"
local longOptions = {"no-create", "help"}

shell.registerCompletion("touch", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
