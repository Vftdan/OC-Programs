local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "qlr"
local longOptions = {"help"}

shell.registerCompletion("flash", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
