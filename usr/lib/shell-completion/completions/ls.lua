local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "ahlrRStX1pM"
local longOptions = {"all", "full-time", "human-readable", "si", "reverse", "recursive", "no-color","help"}

shell.registerCompletion("ls", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
