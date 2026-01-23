local function bindStorage(robot, controller, side)
	local bound = {}
	local function addMethodFrom(source, name)
		bound[name] = function(...)
			return source[name](side, ...)
		end
	end
	for _, name in ipairs{"getInventorySize", "getStackInSlot", "dropIntoSlot", "suckFromSlot", "store", "compareStacks", "getSlotMaxStackSize", "getSlotStackSize"} do
		addMethodFrom(controller, name)
	end
	for _, name in ipairs{"drain", "fill", "drop", "suck"} do
		addMethodFrom(robot, name)
	end
	return bound
end

return {
	bindStorage = bindStorage,
}
