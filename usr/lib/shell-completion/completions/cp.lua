local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "inruPvx"
local longOptions = {"skip="}

shell.registerCompletion("cp", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
