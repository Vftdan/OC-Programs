local serialization = require "serialization"

local function serializeArgs(...)
	local builder = {"("}
	for i = 1, select("#", ...) do
		local arg = select(i, ...)
		table.insert(builder, serialization.serialize(arg))
		table.insert(builder, ",")
	end
	if #builder > 1 then
		builder[#builder] = ")"
	else
		builder[2] = ")"
	end
	return table.concat(builder)
end

return {
	serializeArgs = serializeArgs,
}
