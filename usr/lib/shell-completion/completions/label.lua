local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "a"
local longOptions = {}

shell.registerCompletion("label", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
