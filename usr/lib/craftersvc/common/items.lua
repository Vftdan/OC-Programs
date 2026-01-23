local function matches(stack, specifiers)
	for k, v in pairs(specifiers) do
		if type(v) ~= "table" and stack[k] ~= v then
			return false
		end
	end
	return true
end

return {
	matches = matches,
}
