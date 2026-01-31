local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "qv"
local longOptions = {"bytes=", "lines=", "quiet", "silent", "verbose", "help"}

shell.registerCompletion("head", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
