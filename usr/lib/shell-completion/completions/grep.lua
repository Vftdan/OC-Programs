local shell = require "shell"
local util = require "shell-completion.util"

local shortOptions = "eFwxisvnHhoqrLlct"
local longOptions = {"lua-regexp", "fixed-strings", "file", "word-regexp", "line-regexp", "ignore-case", "label=", "no-messages", "invert-match", "help", "max-count=", "line-number", "with-filename", "no-filename", "only-matching", "quiet", "silent", "recursive", "files-without-match", "files-with-matches", "count", "color", "colour", "trim"}

shell.registerCompletion("grep", {
  populate = function(result, argv)
    return util.populateOptions(result, argv, shortOptions, longOptions)
  end,
})
