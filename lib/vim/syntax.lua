local makeClass = require("vim.makeclass")
local strptn = require("vim.strptn")
local itertools = require("vim.itertools")

local function stackEquals(lhs, rhs)
	if not lhs or not rhs then
		return false
	end
	local len = #lhs
	if #rhs ~= len then
		return false
	end
	for i = 1, len do
		if lhs[i] ~= rhs[i] then
			return false
		end
	end
	return true
end

local function enter(enteredStack, rule)
	table.insert(enteredStack, rule)
end

local function leave(enteredStack, availableStack, rule)
	while #enteredStack do
		local inner = table.remove(enteredStack)
		inner:onLeave(enteredStack, availableStack)
		if inner == rule then
			break
		end
	end
end

local function resetAvailable(availableStack, newRules)
	local entry = {}
	if newRules then
		for _, rule in ipairs(newRules) do
			entry[rule.pattern] = rule
		end
	end
	table.insert(availableStack, entry)
end

local function restoreAvailable(availableStack)
	table.remove(availableStack)
end

local function collectGroupNames(enteredStack)
	local names = {}
	for _, rule in ipairs(enteredStack) do
		table.insert(names, rule.groupName)
	end
	return names
end

local function pushPatternEnd(patternEnds, key, value)
	local index = 1
	for _, entry in ipairs(patternEnds) do
		if entry.key >= key then
			break
		end
		index = index + 1
	end
	table.insert(patternEnds, index, {key = key, value = value})
end

local function peekPatternEnd(patternEnds)
	local entry = patternEnds[1]
	if not entry then
		return nil, nil
	end
	return entry.key, entry.value
end

local function popPatternEnd(patternEnds)
	local entry = table.remove(patternEnds, 1)
	if not entry then
		return nil, nil
	end
	return entry.key, entry.value
end

local function thresholdsToRegions(thresholds, line)
	local regions = {}
	local startByte = 1
	local thresholdIndex = 1
	local lastGroupNames = {}
	local firstCodePoint = 1
	local lineLen = #line
	while startByte <= lineLen do
		local endByte = lineLen + 1
		if thresholds[thresholdIndex] then
			endByte = thresholds[thresholdIndex].index
		end
		while true do
			thresholdIndex = thresholdIndex + 1
			if not thresholds[thresholdIndex] or thresholds[thresholdIndex].index > endByte then
				break
			end
		end
		endByte = endByte - 1
		local lastCodePoint = strptn.unitPointIndex(line, endByte)
		if endByte >= startByte then
			local entry = {
				firstCodePoint = firstCodePoint,
				lastCodePoint = lastCodePoint,
				styleNames = lastGroupNames,
			}
			table.insert(regions, entry)
		end
		firstCodePoint = lastCodePoint + 1
		if thresholds[thresholdIndex - 1] then
			lastGroupNames = thresholds[thresholdIndex - 1].groupNames
		else
			lastGroupNames = {}
		end
		startByte = endByte + 1
	end
	return regions
end

local function findFirstAccepting(line, rule, ptn, start)
	if not rule then
		return nil, nil
	end
	ptn = ptn or rule.pattern
	start = start or 1
	while start <= #line do
		local beg, ed = line:find(ptn, start)
		if not beg then
			return nil, nil
		end
		if rule:acceptsAt(line, beg, ed) then
			return beg, ed
		end
		start = beg + 1
	end
	return nil, nil
end

local MatchRule = makeClass {
	init = function(self, pattern, groupName)
		self.pattern = pattern
		self.groupName = groupName
	end,
	onPatternStart = function(self, enteredStack, availableStack)
		enter(enteredStack, self)
		resetAvailable(availableStack)
	end,
	onLeave = function(self, enteredStack, availableStack)
		restoreAvailable(availableStack)
	end,
	onPatternEnd = function(self, enteredStack, availableStack)
		leave(enteredStack, availableStack, self)
	end,
	acceptsAt = function(self, line, beg, ed)
		return true
	end,
}

local KeywordRule = makeClass {
	init = function(self, pattern, groupName)
		self.pattern = pattern
		self.groupName = groupName
	end,
	onPatternStart = function(self, enteredStack, availableStack)
		enter(enteredStack, self)
		resetAvailable(availableStack)
	end,
	onLeave = function(self, enteredStack, availableStack)
		restoreAvailable(availableStack)
	end,
	onPatternEnd = function(self, enteredStack, availableStack)
		leave(enteredStack, availableStack, self)
	end,
	acceptsAt = function(self, line, beg, ed)
		if line:sub(beg - 1, beg - 1):find("%w") then
			return false
		end
		if line:sub(ed + 1, ed + 1):find("%w") then
			return false
		end
		return true
	end,
}

local Syntax = makeClass {
	init = function(self)
		self._nonce = {}
		self._rules = {}
		self._priorities = {}
		self._lastPriority = 0
	end,
	_invalidate = function(self)
		self._nonce = {}
	end,
	clear = function(self)
		self._rules = {}
		self:_invalidate()
	end,
	defineMatch = function(self, groupName, pattern, opts)
		local priority = self._lastPriority + 1
		self._lastPriority = priority
		self._rules[pattern] = MatchRule(pattern, groupName)
		self._priorities[pattern] = priority
		self:_invalidate()
	end,
	defineKeyword = function(self, groupName, kws, opts)
		local priority = self._lastPriority + 1
		self._lastPriority = priority
		for _, kw in ipairs(kws) do
			local pattern = strptn.escapePtn(kw)
			self._rules[pattern] = KeywordRule(pattern, groupName)
			self._priorities[pattern] = priority
		end
		self:_invalidate()
	end,
	_getLineCache = function(self, buf, lineNr)
		if lineNr < 1 or lineNr > buf:getLineCount() then
			return nil
		end
		local entry = buf:getScopedLineCache(lineNr, "syntax")
		if not entry or entry.nonce ~= self._nonce then
			entry = {nonce = self._nonce}
			buf:setScopedLineCache(lineNr, "syntax", entry)
		end
		return entry
	end,
	updateRange = function(self, buf, firstLine, lastLine)
		local yieldCounter = 0
		for lineNr = firstLine, lastLine do
			self:_updateLineState(buf, lineNr)
			yieldCounter = yieldCounter + 1
			if yieldCounter > 10 then
				yieldCounter = 0
				-- TODO better interface
				buf._editor.typeahead:yieldCPU()
			end
		end
		self:_checkFrom(buf, lastLine + 1)
	end,
	_updateLineState = function(self, buf, lineNr)
		local state = self:_getLineCache(buf, lineNr)
		local prevState = self:_getLineCache(buf, lineNr - 1) or {}
		if stackEquals(state.startStack, prevState.endStack or {}) then
			return false
		end
		local line = buf:getLine(lineNr)
		local thresholds = {}
		local enteredStack = prevState.endStack and itertools.collect(ipairs(prevState.endStack)) or {}
		table.insert(thresholds, {index = 1, groupNames = collectGroupNames(enteredStack)})
		local availableStack
		if prevState.availableStack then
			availableStack = itertools.collect(ipairs(prevState.availableStack))
		else
			availableStack = {self._rules}
		end
		if #availableStack < 1 then
			availableStack[1] = self._rules
		end
		local start = 1
		local nextRuleBounds = {}
		for pattern, rule in pairs(availableStack[#availableStack]) do
			local m = {findFirstAccepting(line, rule, pattern, start)}
			if m[1] then
				nextRuleBounds[pattern] = m
			end
		end
		local patternEnds = {}
		while start <= #line do
			local minPatternIndex = nil
			local minPattern = nil
			for pattern, m in pairs(nextRuleBounds) do
				if m[1] < start then
					m = {findFirstAccepting(line, availableStack[#availableStack][pattern], pattern, start)}
					if not m[1] then
						m = nil
					end
					nextRuleBounds[pattern] = m
				end
				if m then
					if not minPatternIndex or minPatternIndex > m[1] or minPatternIndex == m[1] and self._priorities[minPattern] < self._priorities[pattern] then
						minPatternIndex = m[1]
						minPattern = pattern
					end
				end
			end
			if not minPatternIndex then
				break
			end
			local rule = availableStack[#availableStack][minPattern]
			rule:onPatternStart(enteredStack, availableStack)
			if #availableStack < 1 then
				availableStack[1] = self._rules
			end
			table.insert(thresholds, {index = minPatternIndex, groupNames = collectGroupNames(enteredStack)})
			local patternEnd = nextRuleBounds[minPattern][2]
			pushPatternEnd(patternEnds, patternEnd, rule)
			-- TODO contained patterns
			start = patternEnd + 1
			local newM = {findFirstAccepting(line, rule, minPattern, start)}
			if not newM[1] then
				newM = nil
			end
			nextRuleBounds[minPattern] = newM
			-- TODO account for modified availableStack
			local nextEnd = peekPatternEnd(patternEnds)
			while nextEnd and nextEnd < start do
				local _, endedRule = popPatternEnd(patternEnds)
				endedRule:onPatternEnd(enteredStack, availableStack)
				if #availableStack < 1 then
					availableStack[1] = self._rules
				end
				table.insert(thresholds, {index = nextEnd + 1, groupNames = collectGroupNames(enteredStack)})
				nextEnd = peekPatternEnd(patternEnds)
			end
		end
		state.regions = thresholdsToRegions(thresholds, line)
		state.availableStack = availableStack
		state.endStack = enteredStack
		state.startStack = prevState.endStack and itertools.collect(ipairs(prevState.endStack)) or {}
		return true
	end,
	_checkFrom = function(self, buf, lineNr)
		local yieldCounter = 0
		local numLines = buf:getLineCount()
		while lineNr <= numLines do
			if not self:_updateLineState(buf, lineNr) then
				break
			end
			yieldCounter = yieldCounter + 1
			if yieldCounter > 10 then
				yieldCounter = 0
				-- TODO better interface
				buf._editor.typeahead:yieldCPU()
			end
		end
	end,
	getRegions = function(self, buf, lineNr)
		self:_updateLineState(buf, lineNr)
		local state = self:_getLineCache(buf, lineNr)
		return state.regions
	end,
}

return {
	Syntax = Syntax,
}
