local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "qpv"
local longOptions = {"ignore-fail-on-non-empty", "parents", "verbose", "help"}

shell.registerCompletion("rmdir", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
