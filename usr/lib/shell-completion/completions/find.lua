local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = ""
local longOptions = {"path", "type=", "name=", "iname=", "help"}

shell.registerCompletion("find", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
