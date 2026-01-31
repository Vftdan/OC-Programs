local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "dvq"
local longOptions = {"verbose", "quiet", "help"}

shell.registerCompletion("mktmp", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
