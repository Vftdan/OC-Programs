local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "ahlfipQrStXCR"
local longOptions = {"all", "full-time", "human-readable", "si", "level=", "color=", "quote", "reverse", "help"}

shell.registerCompletion("tree", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
