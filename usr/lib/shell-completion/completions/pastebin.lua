local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "fk"
local longOptions = {}

shell.registerCompletion("pastebin", {
  populate = function(result, argv)
    if #argv == 2 then
      result = {}
      util.populateMatching(result, argv[#argv], {"put", "get", "run"})
      return result
    end
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
