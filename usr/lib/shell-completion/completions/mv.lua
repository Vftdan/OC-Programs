local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "fivnh"
local longOptions = {"skip=", "help"}

shell.registerCompletion("mv", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
