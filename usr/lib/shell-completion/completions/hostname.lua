local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = ""
local longOptions = {"update"}

shell.registerCompletion("hostname", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
