local events = require("vim.platform.events")
local sysencoding = require("vim.platform.sysencoding")
local makeClass = require("vim.makeclass")
local keyseq = require("vim.keyseq")
local Trie = require("vim.trie")
local itertools = require("vim.itertools")

local keyNamesMap = {
	-- CC:
	backspace = "bs",
	enter = "cr",
	tab = "tab",
	numPadEnter = "cr",
	delete = "del",
	minus = "-",
	equals = "=",
	leftBracket = "[",
	rightBracket = "]",
	semiColon = ";",
	apostrophe = "'",
	grave = "`",
	backslash = "backslash",
	comma = ",",
	period = ".",
	slash = "/",
	multiply = "kmultiply",
	space = " ",
	one = "1",
	two = "2",
	three = "3",
	four = "4",
	five = "5",
	six = "6",
	seven = "7",
	eight = "8",
	nine = "9",
	zero = "0",
	numPadAdd = "kplus",
	numPadSubtract = "kminus",
	numPadDecimal = "kpoint",
	numPadEquals = "kequal",
	numPadComma = "kcomma",
	numPadDivide = "kdivide",
	numPad0 = "k0",
	numPad1 = "k1",
	numPad2 = "k2",
	numPad3 = "k3",
	numPad4 = "k4",
	numPad5 = "k5",
	numPad6 = "k6",
	numPad7 = "k7",
	numPad8 = "k8",
	numPad9 = "k9",
	yen = sysencoding.fromCodePoint(0xa5) or "\xa5",
	circumflex = "^",
	at = "@",
	colon = ":",
	underscore = "_",
	-- remaining OC:
	back = "bs",
	numpadenter = "cr",
	lbracket = "[",
	rbracket = "]",
	semicolon = ";",
	numpadmul = "kmultiply",
	numpadadd = "kplus",
	numpadsub = "kminus",
	numpaddecimal = "kpoint",
	numpadequals = "kequal",
	numpadcomma = "kcomma",
	numpaddiv = "kdivide",
	numpad0 = "k0",
	numpad1 = "k1",
	numpad2 = "k2",
	numpad3 = "k3",
	numpad4 = "k4",
	numpad5 = "k5",
	numpad6 = "k6",
	numpad7 = "k7",
	numpad8 = "k8",
	numpad9 = "k9",
	underline = "_",
}

local identityMappedKeys = {
	"left", "right", "up", "down",
	"f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15", "f16", "f17", "f18", "f19",
	"home", "end", "pageUp", "pageDown", "insert",
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
}

local modNamesMap = {
	-- CC:
	leftCtrl = "C",
	rightCtrl = "C",
	leftAlt = "A",
	rightAlt = "A",
	leftShift = "S",
	rightShift = "S",
	-- OC:
	lcontrol = "C",
	rcontrol = "C",
	lmenu = "A",
	rmenu = "A",
	lshift = "S",
	rshift = "S",
}

local mouseNamesMap = {
	left = "leftmouse",
	right = "rightmouse",
	middle = "middlemouse",
}

local builtinKeyCharacters = {
	lt = "<",
	space = " ",
	backslash = "\\",
	bar = "|",
	kmultiply = "*",
	kplus = "+",
	kminus = "-",
	kpoint = ".",
	kequal = "=",
	kcomma = ",",
	kdivide = "/",
	k0 = "0",
	k1 = "1",
	k2 = "2",
	k3 = "3",
	k4 = "4",
	k5 = "5",
	k6 = "6",
	k7 = "7",
	k8 = "8",
	k9 = "9",
}

local keyNormalisation = {
	["<"] = "lt",
	-- [">"] = "gt",
	[" "] = "space",
	["\\"] = "backslash",
	["|"] = "bar",
	["esc"] = "tab",  -- consider handling `esc` together with `leader` and `localleader`
}

local modifierOrder = {"C", "A", "S"}

local keyNames = {}

for nativeName, vimName in pairs(keyNamesMap) do
	local scanCode = events.keyScanCodes[nativeName]
	if scanCode then
		keyNames[scanCode] = vimName
	end
end

for _, nativeName in ipairs(identityMappedKeys) do
	local vimName = nativeName:lower()
	local scanCode = events.keyScanCodes[nativeName]
	if scanCode then
		keyNames[scanCode] = vimName
	end
end

local modifierNames = {}

for nativeName, vimName in pairs(modNamesMap) do
	local scanCode = events.keyScanCodes[nativeName]
	if scanCode ~= nil then
		modifierNames[scanCode] = vimName
	end
end

local function isCharacterKey(name)
	if sysencoding.len(name) == 1 then
		return true
	end
	if builtinKeyCharacters[name] ~= nil then
		return true
	end
	return false
end

local function getSelfInsert(name)
	if sysencoding.len(name) == 1 then
		return name
	end
	local ch = builtinKeyCharacters[name]
	if ch ~= nil then
		return ch
	end
	return "<" .. name .. ">"
end

local function prependModifiers(translatedKey, mods, order)
	order = order or modifierOrder
	for _, name in itertools.reversedIpairs(order) do
		if mods[name] then
		    translatedKey = name .. "-" .. translatedKey
		end
	end
	return translatedKey
end

local Typeahead = makeClass {
	init = function(self)
		self.ignoreHold = {}
		self._queue = {}
		self._running = true
		self.inputProperties = {mouseX = 1, mouseY = 1, pasteData = ""}
		self._modeMappings = nil
		self._langMappings = nil
		self._fallbackEventHandlers = {}
		self._preWaitHandlers = {}
		self._activeModifiers = {}
		self._prefixedModifiers = {}
	end,
	getLength = function(self)
		return #self._queue
	end,
	insert = function(self, charname, kwargs)
		kwargs = kwargs or {}
		local index = kwargs.index or #self._queue + 1
		local update = {}
		if self._scheduledPropertyUpdate then
			itertools.update(update, self._scheduledPropertyUpdate)
			self._scheduledPropertyUpdate = nil
		end
		if kwargs.update then
			itertools.update(update, kwargs.update)
		end
		charname = keyseq.normalizeKey(charname, keyNormalisation, modifierOrder)
		table.insert(self._queue, index, {
			name = charname,
			update = update,
			noModeMap = kwargs.noModeMap or false,
			noLangMap = kwargs.noLangMap or false,  -- should it be separate from mode mapping?
		})
	end,
	pull = function(self)
		local item = table.remove(self._queue, 1)
		while item == nil do
			if not self._running then
				return nil
			end
			self:waitForEvent()
			item = table.remove(self._queue, 1)
		end
		itertools.update(self.inputProperties, item.update)
		return item.name
	end,
	_peekRaw = function(self, idx)
		idx = idx or 1
		while #self._queue < idx do
			if not self._running then
				return nil
			end
			self:waitForEvent()
		end
		return self._queue[idx]
	end,
	peek = function(self, idx)
		local item = self:_peekRaw(idx)
		if item == nil then
			return nil
		end
		return item.name
	end,
	setModeMappings = function(self, trie)
		self._modeMappings = trie
	end,
	setLangMappings = function(self, trie)
		self._langMappings = trie
	end,
	getModeMappings = function(self)
		return self._modeMappings
	end,
	getLangMappings = function(self)
		return self._langMappings
	end,
	_applyMappingsOnce = function(self, trie, flagField)
		if trie == nil then
			return false
		end
		local i = 0
		local cons = trie:consumer()
		while true do
			i = i + 1
			local key = self:peek(i)
			if key == nil then
				break
			end
			if not cons:next(key) then
				break
			end
			if not cons:hasNext() then
				break
			end
		end
		local len, entry = cons:getDeepest()
		if len > 0 then
			local dst = entry.dst or {}
			if #dst < 1 then
				for _ = 1, len do
					self:pull()
				end
			else
				local saveProps = self.inputProperties
				self.inputProperties = {}
				for _ = 1, len do
					self:pull()
				end
				local squashedUpdate = self.inputProperties
				self.inputProperties = saveProps
				self:insert(dst[1], {update = squashedUpdate, index = 1, [flagField] = not entry.remap})
				for i = 2, #dst do
					self:insert(dst[i], {index = i, [flagField] = not entry.remap})
				end
			end
		else
			local first = self:_peekRaw()
			if first then
				first[flagField] = true  -- Is this a correct optimization?
			end
			return false
		end
		return true
	end,
	applyModeMappings = function(self)
		while true do
			local first = self:_peekRaw()
			if first == nil then
				break
			end
			if first.noModeMap then
				break
			end
			if not self:_applyMappingsOnce(self._modeMappings, "noModeMap") then
				break
			end
		end
	end,
	applyLangMappings = function(self)
		while true do
			local first = self:_peekRaw()
			if first == nil then
				break
			end
			if first.noLangMap then
				break
			end
			if not self:_applyMappingsOnce(self._langMappings, "noLangMap") then
				break
			end
		end
	end,
	waitForEvent = function(self)
		for _, f in ipairs(self._preWaitHandlers) do
			f()
		end
		local ev = events.pullNative()
		self:_handleNativeEvent(ev)
	end,
	getLatestModifiers = function(self, resetPrefixed)
		local result = {}
		local k, v
		for k, v in pairs(self._activeModifiers) do
			if v then
				result[modifierNames[k]] = true
			end
		end
		for k, v in pairs(self._prefixedModifiers) do
			if v then
				result[modifierNames[k]] = true
				if resetPrefixed then
					self._prefixedModifiers[k] = nil
				end
			end
		end
		return result
	end,
	schedulePropertyUpdate = function(self, update)
		self._scheduledPropertyUpdate = update
	end,
	_handleNativeEvent = function(self, ev)
		if events.isInterrupt(ev) then
			error("Interrupted")
		end
		local flag, data
		flag, data = events.isKeyPressOrChar(ev)
		if flag then
			-- when ctrl is actually held, printable keys are handled by scancode, otherwise by text
			local ctrlHeld = false
			for modCode, modHeld in pairs(self._activeModifiers) do
				if modHeld and modifierNames[modCode] == "C" then
					ctrlHeld = true
					break
				end
			end
			if not ctrlHeld and data.text and data.printable then
				local s = data.text
				local mods = self:getLatestModifiers(true)
				s = prependModifiers(s, mods, {
					"C",
					-- Warning: AltGr might generate unwanted alt modification
					"A",
					-- Do not add shift, because it should already be consumed by the key to char conversion
					-- "S",
				})
				self:insert(s)
			elseif data.scanCode then
				local s = data.scanCode
				local translatedKey = keyNames[s]
				local translatedMod = modifierNames[s]
				if translatedKey ~= nil then
					translatedKey = keyNormalisation[translatedKey:lower()] or translatedKey
					-- Only if the key event will not be doubled by a char event (only required in CC)
					if not isCharacterKey(translatedKey) or ctrlHeld then
						local mods = self:getLatestModifiers(true)
						translatedKey = prependModifiers(translatedKey, mods)
						self:insert(translatedKey)
					end
				elseif translatedMod ~= nil then
					if (data.held and not self._activeModifiers[s]) or self.ignoreHold[s] then
						-- If a key sends a repeat event without a start event,
						-- it will not send key_up
						-- TODO this is an CC old code, figure out what I meant
						self._prefixedModifiers[s] = not self._prefixedModifiers[s]
					else
						self._activeModifiers[s] = true
						if self._prefixedModifiers[s] then
							self._prefixedModifiers[s] = nil  -- Repeated modifier presses remove the prefixed state
						else
							self._prefixedModifiers[s] = not data.held  -- Only prefixed if not held
							-- FIXME repeats for the modifier keys seem to not be sent
						end
					end
				end
			end
			flag = false
		else
			flag, data = events.isKeyUp(ev)
		end
		if flag then
			local s = data.scanCode
			local translatedMod = modifierNames[s]
			if translatedMod ~= nil then
				self._activeModifiers[s] = nil  -- No longer active
				-- But remain prefixed
			end
			return
		end
		flag, data = events.isMouseDown(ev)
		if flag then
			local buttonName = data.button and events.mouseButtonNames[data.button]
			local translatedKey = buttonName and mouseNamesMap[buttonName]
			local mods = self:getLatestModifiers(true)
			if translatedKey == nil then
				-- Is this reachable?
				-- Remains from CCVim's feature to leave insert mode with touch
				translatedKey = "tab"
			else
				translatedKey = prependModifiers(translatedKey, mods)
			end
			self:insert(translatedKey, {update = {mouseX = data.x, mouseY = data.y}})
			return
		end
		flag, data = events.isMouseScroll(ev)
		if flag then
			local mods = self:getLatestModifiers(true)
			if data.dy ~= 0 then
				local absAmount = data.dy
				local translatedKey = "scrollwheeldown"
				if absAmount < 0 then
					absAmount = -absAmount
					translatedKey = "scrollwheelup"
				end
				translatedKey = prependModifiers(translatedKey, mods)
				for i = 1, absAmount do
					self:insert(translatedKey, {update = {mouseX = data.x, mouseY = data.y}})
				end
			end
			if data.dx ~= 0 then  -- currently not supported anywhere
				local absAmount = data.dx
				local translatedKey = "scrollwheelright"
				if absAmount < 0 then
					absAmount = -absAmount
					translatedKey = "scrollwheelleft"
				end
				translatedKey = prependModifiers(translatedKey, mods)
				for i = 1, absAmount do
					self:insert(translatedKey, {update = {mouseX = data.x, mouseY = data.y}})
				end
			end
			return
		end
		flag, data = events.isPaste(ev)
		if flag then
			self:schedulePropertyUpdate({pasteData = data.text})
			if data.consumedEvent then
				self:_handleNativeEvent(data.consumedEvent)
			end
			return
		end
		for _, f in ipairs(self._fallbackEventHandlers) do
			f(ev)
		end
	end,
	terminate = function(self)
		self._running = false
	end,
	stringifyQueue = function(self)
		local seq = {}
		for index, item in ipairs(self._queue) do
			seq[index] = item.name
		end
		return keyseq.stringifyKeySequence(seq)
	end,
	stringifyModifiers = function(self)
		local mods = self:getLatestModifiers(false)
		return prependModifiers("", mods)
	end,
	stringifyAll = function(self)
		local queueStr = self:stringifyQueue()
		local modStr = self:stringifyModifiers()
		if #modStr > 0 then
			return queueStr .. "<" .. modStr
		end
		return queueStr
	end,
	addFallbackEventHandler = function(self, cb)
		table.insert(self._fallbackEventHandlers, cb)
	end,
	addPreWaitHandler = function(self, cb)
		table.insert(self._preWaitHandlers, cb)
	end,
}

return {
	Typeahead = Typeahead,
	keyNormalisation = keyNormalisation,
	modifierOrder = modifierOrder,
	getSelfInsert = getSelfInsert,
}
