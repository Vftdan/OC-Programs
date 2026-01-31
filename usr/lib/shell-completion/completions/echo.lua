local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "ne"
local longOptions = {"help"}

shell.registerCompletion("echo", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
