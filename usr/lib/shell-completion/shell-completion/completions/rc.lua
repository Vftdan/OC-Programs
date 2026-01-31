local shell = require "shell"
local filesystem = require "filesystem"
local math = require "math"
local rc = require "rc"
local util = require "shell-completion.util"

local function getServices()
  local services = {}
  local added = {}
  for fname in filesystem.list("/etc/rc.d") do
    local baseLen = math.max(0, #fname - 4)
    if fname:sub(baseLen + 1) == ".lua" then
      local name = fname:sub(1, baseLen)
      added[name] = true
      table.insert(services, name)
    end
  end
  for name in pairs(rc.loaded) do
    if not added[name] then
      table.insert(services, name)
    end
  end
  return services
end

local function getSubcommands(svc)
  local api = rc.loaded[svc]
  if not api then
    return {"start", "stop", "restart", "enable", "disable"}
  end
  local result = {}
  local added = {_complete = true}
  for k, v in pairs(api) do
    if type(v) == "function" and not added[k] then
      added[k] = true
      table.insert(result, k)
    end
  end
  for _, k in ipairs{"start", "stop", "restart", "enable", "disable"} do
    if not added[k] then
      added[k] = true
      table.insert(result, k)
    end
  end
  return result
end

local function getSvcCompletion(svc)
  local api = rc.loaded[svc]
  if not api then
    return nil
  end
  local handler = api._complete
  if type(handler) ~= "function" then
    return nil
  end
  return handler
end

shell.registerCompletion("rc", {
  noBuiltin = true,
  populate = function(result, argv)
    if #argv == 2 then
      util.populateMatching(result, argv[#argv], getServices())
    elseif #argv == 3 then
      util.populateMatching(result, argv[#argv], getSubcommands(argv[2]))
    elseif #argv > 3 then
      local handler = getSvcCompletion(argv[2])
      if handler then
        local arr = handler(table.unpack(argv, 3))
        if type(arr) == "table" then
          util.populateMatching(result, argv[#argv], arr)
        end
      end
    end
  end
})
