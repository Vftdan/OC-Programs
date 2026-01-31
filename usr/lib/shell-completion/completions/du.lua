local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "hs"
local longOptions = {"human-readable", "summarize", "help", "version"}

shell.registerCompletion("du", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
