local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = ""
local longOptions = {"help"}

shell.registerCompletion("list", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
