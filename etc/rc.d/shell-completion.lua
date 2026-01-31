-- partially based on /lib/core/full_sh.lua

local sh = require "sh"
local shell = require "shell"
local unicode = require "unicode"
local text = require "text"

local fallback = sh.internal.hintHandlerImpl
local enabled = false
local doComplete
local registry = {}

local function wrapper(fullLine, cursor, ...)
  if not enabled then
    return fallback(fullLine, cursor, ...)
  end

  local line = unicode.sub(fullLine, 1, cursor - 1)
  local suffix = unicode.sub(fullLine, cursor)

  local success, result = pcall(doComplete, fullLine, cursor, line, suffix, ...)
  if not success then
    print("\n", result)
  end
  if not success or not result then
    return fallback(fullLine, cursor, ...)
  end
  return result
end

sh.internal.hintHandlerImpl = wrapper

function shell.registerCompletion(program, options)
  checkArg(1, program, "string")
  checkArg(2, options, "table")
  registry[program] = options
end

local function getSplits(line)
  local splits = text.internal.tokenize(line, {show_escapes = true})
  if not splits then
    return nil
  end

  local lastClose = 0
  for index = #splits, 1, -1 do
    local word = splits[index]
    if sh.internal.isWordOf(word, {";", "&&", "||", "|"}) then
      lastClose = index
      break
    end
  end

  if line:match("%s$") then
    table.insert(splits, {{txt = ""}})
  end

  return splits, lastClose
end

function doComplete(fullLine, cursor, line, suffix, ...)
  local prefix = sh.internal.hintHandlerSplit(line)
  local splits, lastClose = getSplits(line)
  if not prefix or not splits then
    return nil
  end

  local curArgv = {table.unpack(splits, lastClose + 1)}
  if #curArgv < 2 then
    return nil
  end
  curArgv = text.internal.normalize(curArgv)
  local cmd = curArgv[1]

  pcall(require, "shell-completion.completions." .. cmd)
  local options = registry[cmd]
  if not options then
    return nil
  end

  local result
  if options.noBuiltin then
    result = {}
  else
    result = sh.getMatchingFiles(curArgv[#curArgv])
    table.sort(result)
  end

  if type(options.populate) == "function" then
    local newResult = options.populate(result, curArgv)
    if type(newResult) == "table" then
      result = newResult
    end
  end

  for i, v in ipairs(result) do
    result[i] = prefix .. v .. suffix
  end

  return result
end

function start()
  enabled = true
end

function stop()
  enabled = false
end

-- vim: et ts=2
