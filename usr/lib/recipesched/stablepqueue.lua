local proto = {}
local meta = {__index = proto}

function proto:less_than(lhs, rhs)
	return lhs < rhs
end

function proto:put(key, elem)
	local entry = {key, elem}
	local prev_idx = #self._items
	while prev_idx > 0 do
		local prev_entry = self._items[prev_idx]
		if self:less_than(key, prev_entry[1]) then
			prev_idx = prev_idx - 1
		else
			break
		end
	end
	table.insert(self._items, prev_idx + 1, entry)
end

function proto:take()
	local entry = table.remove(self._items, 1)
	if not entry then
		return
	end
	return entry[1], entry[2]
end

local function create()
	return setmetatable({_items = {}}, meta)
end

return {
	create = create,
}
