local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "fqQ"
local longOptions = {}

shell.registerCompletion("wget", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
