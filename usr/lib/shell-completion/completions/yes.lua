local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "Vh"
local longOptions = {"version", "help"}

shell.registerCompletion("yes", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
