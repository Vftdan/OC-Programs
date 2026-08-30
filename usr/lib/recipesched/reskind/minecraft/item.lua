local handlers = {}

function handlers.populateFields(value, fields)
	value.damage = fields.damage
	value.maxSize = fields.maxSize
	value.label = fields.label
end

function handlers.finalizeValue(stack)
	--[[ Transposer stack fields:
	-- name: string
	-- label: string
	-- damage: number
	-- maxDamage: number
	-- size: number
	-- maxSize: number
	-- hasTag: boolean
	-- with Thaumic Computers: aspects: nil | table<string, number>
	-- with Forestry integration: individual: nil | table{
	--     displayName: string (only species word)
	--     type: string ("bee", ...)
	--     maxHealth: number
	--     canSpawn: boolean
	--     isAlive: boolean
	--     isAnalyzed: boolean
	--     isSecret: boolean
	--     generation: number
	--     health: number isNatural: boolean
	--     hasEffect: boolean
	--     ident: string (species)
	--     active: .isAnalyzed ? table<string, string | number | boolean> : nil
	--     inactive: .isAnalyzed ? table<string, string | number | boolean> : nil
	-- }
	--]]
	if type(stack) ~= "table" then
		return false, ": table expected, got " .. type(stack)
	end
	local name = stack.name
	if type(name) ~= "string" then
		return false, ".name: string expected, got " .. type(name)
	end
	local damage = stack.damage
	if damage ~= nil and type(damage) ~= "number" then
		return false, ".damage: number or nil expected, got " .. type(damage)
	end
	local maxSize = stack.maxSize
	if maxSize == nil then
		maxSize = 64
	end
	if type(maxSize) ~= "number" then
		return false, ".maxSize: number or nil expected, got " .. type(maxSize)
	end
	local label = stack.label
	if label ~= nil and type(label) ~= "string" then
		return false, ".label: string expected, got " .. type(label)
	end
	return true, {name = name, damage = damage, maxSize = maxSize, label = label}
end

function handlers.getSpecifiers(stack)
	return {name = stack.name, damage = stack.damage, maxSize = stack.maxSize, label = stack.label}
end

function handlers.setAmount(stack, amount)
	stack.size = amount
end

return handlers
