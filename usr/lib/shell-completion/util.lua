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

return {
  hasPrefix = hasPrefix,
  populateMatching = populateMatching,
}
