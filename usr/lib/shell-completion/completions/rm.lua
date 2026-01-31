local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "fiIrRdv"
local longOptions = {"force", "one-file-system", "no-preserve-root", "preserve-root", "recursive", "dir", "verbose", "help"}

shell.registerCompletion("rm", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
