local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "rh"
local longOptions = {"readonly", "bind", "help"}

shell.registerCompletion("mount", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
