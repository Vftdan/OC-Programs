local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "u"
local longOptions = {"from=", "to=", "fromDir=", "root=", "toDir=", "update", "label", "nosetlabel", "nosetboot", "noreboot", "help"}

shell.registerCompletion("install", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
