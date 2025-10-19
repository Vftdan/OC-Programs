local makeClass = require("vim.makeclass")

local Trie = makeClass {
	init = function(self)
		self._value = nil
		self._next = {}
	end,
	put = function(self, key, value)
		self:putIter({ipairs(key)}, value)
	end,
	remove = function(self, key)
		self:removeIter({ipairs(key)})
	end,
	putIter = function(self, it, value)
		if value == nil then
			self:remove(it)
			return
		end
		local i, e = it[1](it[2], it[3])
		if i == nil then
			self._value = value
		else
			it[3] = i
			local child = self._next[e] or self.new()
			self._next[e] = child
			child:putIter(it, value)
		end
	end,
	removeIter = function(self, it)
		local i, e = it[1](it[2], it[3])
		if i == nil then
			self._value = nil
		else
			it[3] = i
			local child = self._next[e]
			if child ~= nil then
				self._next[e] = child:removeIter(it)
			end
		end
		if next(self._next) ~= nil or self._value ~= nil then
			return self
		else
			return nil
		end
	end,
	consumer = function(self)
		return self.Consumer.new({self})
	end,
	Consumer = makeClass {
		init = function(self, tries)
			self._roots = tries
			self._numTries = tries.n or #tries
			self._nodes = table.pack(table.unpack(tries))
			self._depth = 0
			self._lastFound = -1
			self._lastValue = nil
			self._lastIndex = -1
			for i = 1, self._numTries do
				local t = tries[i]
				local v = t._value
				if v then
					self._lastValue = v
					self._lastFound = 0
					self._lastIndex = i
				end
			end
		end,
		hasNext = function(self)
			local result = false
			for i = 1, self._numTries do
				local node = self._nodes[i]
				if node ~= nil then
					if next(node._next) ~= nil then
						result = true
					end
				end
			end
			return result
		end,
		next = function(self, e)
			local result = false
			local children = self._backNodes or {}  -- slightly reduce allocations
			local depth = self._depth + 1
			for i = 1, self._numTries do
				local node = self._nodes[i]
				children[i] = nil
				if node ~= nil then
					local child = node._next[e]
					children[i] = child
					if child ~= nil then
						result = true
						local value = child._value
						if value ~= nil then
							self._lastFound = depth
							self._lastValue = value
							self._lastIndex = i
						end
					end
				end
			end
			if result then
				self._depth = depth
				self._backNodes = self._nodes
				self._nodes = children
			end
			return result
		end,
		getDeepest = function(self)
			return self._lastFound, self._lastValue, self._lastIndex
		end,
	}
}

return Trie
