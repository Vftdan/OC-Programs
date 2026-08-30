local handlers = {}

function handlers.populateFields(value, fields)
	value.label = fields.label
end

function handlers.finalizeValue(stack)
	--[[ Transposer fluid stack fields:
	-- name: string
	-- label: string
	-- amount: number
	-- hasTag: boolean
	--]]
	if type(stack) ~= "table" then
		return false, ": table expected, got " .. type(stack)
	end
	local name = stack.name
	if type(name) ~= "string" then
		return false, ".name: string expected, got " .. type(name)
	end
	local label = stack.label
	if label ~= nil and type(label) ~= "string" then
		return false, ".label: string expected, got " .. type(label)
	end
	return true, {name = name, label = label}
end

function handlers.getSpecifiers(stack)
	return {name = stack.name, label = stack.label}
end

function handlers.setAmount(stack, amount)
	stack.amount = amount
end

return handlers
