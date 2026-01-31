local function hasPrefix(str, prefix)
  return str:sub(1, #prefix) == prefix
end

local function populateMatching(result, prefix, arr)
  for _, str in ipairs(arr) do
    if hasPrefix(str, prefix) then
      table.insert(result, str)
    end
  end
end

local function populateOptions(result, argvOrPrefix, shortOptions, longOptions)
  local prefix
  if type(argvOrPrefix) == "string" then
    prefix = argvOrPrefix
  else
    prefix = argvOrPrefix[#argvOrPrefix]
  end
  if prefix:sub(1, 1) ~= "-" then
    -- Do not show options if not requested
    return
  end
  local arr = {}
  if prefix:sub(1, 2) == "--" and type(longOptions) == "table" then
    for _, name in ipairs(longOptions) do
      local option = "--" .. name
      if not name:match("%=$") then
        option = option .. " "
      end
      table.insert(arr, option)
    end
  elseif type(shortOptions) == "string" then
    for ch in shortOptions:gmatch(".") do
      table.insert(arr, "-" .. ch)
    end
  end
  return populateMatching(result, prefix, arr)
end

return {
  hasPrefix = hasPrefix,
  populateMatching = populateMatching,
  populateOptions = populateOptions,
}
