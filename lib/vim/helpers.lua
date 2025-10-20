local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")
local textrender = require("vim.platform.textrender")
local strptn = require("vim.strptn")
local typeahead = require("vim.typeahead")
local modes

local function appendTextAtBuffer(editor, buf, tbl, x, y)
	if buf == nil then
		return
	end
	local oldLine = buf:getLine(y)
	local oldLineLen = sysencoding.len(oldLine)
	if x < 0 then
		x = 0
	elseif x > oldLineLen then
		x = oldLineLen
	end
	buf:setTextBetween(tbl, x + 1, y, x, y)
end

local function appendTextAt(editor, tbl, x, y)
	appendTextAtBuffer(editor, editor:getCurrentBuffer(), tbl, x, y)
end

local function applyMotionToContext(editor, toCtx, toDef)
	local defOptions = toDef[1]
	local defFunction = toDef[2]
	if defOptions then
		itertools.update(toCtx, defOptions)
	end
	toCtx = defFunction(editor, toCtx)
	return toCtx
end

local function applyOperator(editor, op, to)
	op(editor, to)
end

local emptyRegisterValue = {lines = {""}}

local makeMotionContext, finalizeMotion

local function evaluateTextObject(editor, toDef)
	local toCtx = makeMotionContext(editor)
	toCtx = applyMotionToContext(editor, toCtx, toDef)
	local to = finalizeMotion(editor, toCtx)
	return to
end

local function expandPaste(editor, opts)
	opts = opts or {}
	local str = editor.typeahead.inputProperties.pasteData or ""
	for i = 1, sysencoding.len(str) do
		local ch = sysencoding.sub(str, i, i)
		editor.typeahead:insert(ch, {index = i, noModeMap = opts.noModeMap, noLangMap = opts.noLangMap, update = opts.update})
	end
end

function finalizeMotion(editor, toCtx)
	return toCtx
end

local function findCharacterInLine(editor, ch, toCtx, opts)
	opts = opts or {}
	toCtx = toCtx or makeMotionContext(editor)
	local buf = editor:getCurrentBuffer()
	if not buf then
		return nil
	end
	local line = buf:getLine(toCtx.y)
	if not line then
		return nil
	end
	local cache = buf:getScopedLineCache(toCtx.y, "characterPos")
	if cache == nil then
		cache = {}
		buf:setScopedLineCache(toCtx.y, "characterPos", cache)
	end
	local matches = cache[ch]
	if not matches then
		matches = strptn.findAll(line, ch)
		-- TODO lru eviction?
		cache[ch] = matches
	end
	local m = strptn.matchesGetAdjacent(matches, toCtx.x, 1, {backward = opts.backward or false, count = opts.count or 1})
	if not m then
		return nil
	end
	return m[1]
end

local function findWordInLine(editor, toCtx, opts)
	opts = opts or {}
	toCtx = toCtx or makeMotionContext(editor)
	local buf = editor:getCurrentBuffer()
	if not buf then
		return nil
	end
	local line = buf:getLine(toCtx.y)
	if not line then
		return nil
	end
	local matches
	if opts.WORDs then
		matches = buf:getScopedLineCache(toCtx.y, "WORDs")
		if not matches then
			matches = strptn.findNonSpaceBoundaries(line)
			buf:setScopedLineCache(toCtx.y, "WORDs", matches)
		end
	else
		matches = buf:getScopedLineCache(toCtx.y, "words")
		if not matches then
			matches = strptn.findWordBoundaries(line)
			buf:setScopedLineCache(toCtx.y, "words", matches)
		end
	end
	local key = 1
	if opts.wordEnd then
		key = 2
	end
	local m, remainingCount = strptn.matchesGetAdjacent(matches, toCtx.x, key, {backward = opts.backward or false, count = opts.count or 1})
	if not m then
		return nil, remainingCount
	end
	return m[key]
end

local function getRegisterValueText(editor, regValue)
	return regValue.lines
end

local function getRepeatCount0(editor)
	return editor._repeatCount or 0
end

local function getRepeatCount1(editor)
	local num = getRepeatCount0(editor)
	if num == 0 then
		return 1
	end
	return num
end

local function getSelectedRegister(editor)
	-- TODO registers
	return editor._unnamedRegister or emptyRegisterValue
end

local getTextObjectEnds

local function getTextObjectAsRegister(editor, to)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local txt
	if to.linewise then
		-- Don't insert a leading/trailing line break like getTextObjectEnds does
		local begX, begY, edX, edY = to.initialX, to.initialY, to.x, to.y
		if begY > edY then
			begY, edY = edY, begY
		end
		txt = {}
		for y = begY, edY do
			table.insert(txt, buf:getLine(y))
		end
	else
		txt = buf:getTextBetween(getTextObjectEnds(editor, to))
		if txt == nil then
			return nil
		end
	end
	return {
		lines = txt,
		linewise = to.linewise,
	}
end

function getTextObjectEnds(editor, to)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local begX, begY, edX, edY = to.initialX, to.initialY, to.x, to.y
	if to.empty and begY == edY and begX == edX + 1 then
		return begX, begY, edX, edY  -- TODO still check whether it is in-bounds
	end
	if edY < begY or edY == begY and edX < begX then
		begX, edX = edX, begX
		begY, edY = edY, begY
	end
	local lineCount = buf:getLineCount()
	local beforeSOB = false
	local afterEOB = false
	if begY < 1 then
		beforeSOB = true
		begY = 1
		begX = 1
	end
	if edY > lineCount then
		afterEOB = true
		edY = lineCount
	end
	local edLine = buf:getLine(edY)
	if afterEOB then
		edX = sysencoding.len(edLine)
		if to.exclusive then
			edX = edX + 1
		end
	end
	if to.linewise then
		if edY >= lineCount then
			if begY <= 1 then
				-- whole buffer
				return 1, 1, sysencoding.len(edLine), edY
			end
			begY = begY - 1
			local begLine = buf:getLine(begY)
			begX = sysencoding.len(begLine) + 1
			edX = sysencoding.len(edLine)
		else
			begX = 1
			edY = edY + 1
			edX = 0
		end
	elseif to.exclusive then
		edX = edX - 1
	end
	return begX, begY, edX, edY
end

local textObjects, registerValueFromText, updateCursorFromMotionContext, setTextObjectAsRegister, scrollToMotionContextEnd

local function insertTextAtCursor(editor, txt)
	local cursorToCtx = makeMotionContext(editor)
	if cursorToCtx == nil then
		return
	end
	cursorToCtx.exclusive = true
	local cursorTo = finalizeMotion(editor, cursorToCtx)
	local fakeRegValue = registerValueFromText(editor, txt)
	setTextObjectAsRegister(editor, cursorTo, fakeRegValue)
	if #txt == 1 then
		cursorToCtx.x = cursorToCtx.x + sysencoding.len(txt[1])
	else
		cursorToCtx.y = cursorToCtx.y + #txt - 1
		cursorToCtx.x = 1 + sysencoding.len(txt[#txt])
	end
	scrollToMotionContextEnd(editor, cursorToCtx)
	updateCursorFromMotionContext(editor, cursorToCtx)
end

local function isEmptyTextObject(editor, to)
	return to.empty
end

function makeMotionContext(editor)
	-- TODO cursor
	local toCtx = {
		initialX = editor._cursorX or 1,
		initialY = editor._cursorY or 1,
		wantX = editor._cursorWantX,
	}
	toCtx.x = toCtx.initialX
	toCtx.y = toCtx.initialY
	return toCtx
end

local function motionContextIntoBounds(editor, toCtx, opts)
	opts = opts or {}
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local lineCount = buf:getLineCount()
	if toCtx.y > lineCount then
		toCtx.y = lineCount
	end
	if toCtx.y < 1 then
		toCtx.y = 1
	end
	local line = buf:getLine(toCtx.y)
	local lineLength = sysencoding.len(line)
	if opts.onePastEnd then
		lineLength = lineLength + 1
	end
	if toCtx.x > lineLength then
		toCtx.x = lineLength
	end
	if toCtx.x < 1 then
		toCtx.x = 1
	end
end

local function performCursorMotion(editor, toDef, opts)
	local toCtx = makeMotionContext(editor)
	if toCtx == nil then
		return false
	end
	toCtx = applyMotionToContext(editor, toCtx, toDef)
	if toCtx == nil then
		return false
	end
	motionContextIntoBounds(editor, toCtx, opts)
	scrollToMotionContextEnd(editor, toCtx)
	updateCursorFromMotionContext(editor, toCtx)
	return true
end

local function performWordMotion(editor, toCtx, opts)
	opts = opts or {}
	local origX, origY = toCtx.x, toCtx.y
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local lineCount = buf:getLineCount()
	local repeatCount = getRepeatCount1(editor)
	local newX
	local yieldCounter = 0
	while editor:isRunning() and toCtx.y >= 1 and toCtx.y <= lineCount do
		newX, repeatCount = findWordInLine(editor, toCtx, {backward = opts.backward, wordEnd = opts.wordEnd, WORDs = opts.WORDs, count = repeatCount})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
			return toCtx
		end
		if opts.backward then
			toCtx.y = toCtx.y - 1
			toCtx.x = sysencoding.len(buf:getLine(toCtx.y) or "") + 1
		else
			toCtx.y = toCtx.y + 1
			toCtx.x = 0
		end
		yieldCounter = yieldCounter + 1
		if yieldCounter > 10 then
			yieldCounter = 0
			editor.typeahead:yieldCPU()
		end
	end
	toCtx.x, toCtx.y = origX, origY
	return toCtx
end

local function pullCountString(editor)
	editor.typeahead:applyModeMappings()
	local ch = editor.typeahead:peek()
	if ch:find("[^1-9]") then
		return ""
	end
	editor.typeahead:pull()
	local builder = {ch}
	while editor:isRunning() do
		ch = editor.typeahead:peek()
		if ch:find("%D") then
			return table.concat(builder)
		end
		editor.typeahead:pull()
		table.insert(builder, ch)
	end
	return nil
end

local function pullInputCharacter(editor)
	editor.typeahead:applyModeMappings()
	editor.typeahead:applyLangMappings()
	local ch = typeahead.getSelfInsert(editor.typeahead:pull())
	if sysencoding.len(ch) ~= 1 then
		return nil
	end
	return ch
end

local runMode

local function pullTextObject(editor)
	if modes == nil then
		modes = require("vim.modes")
	end
	local to = runMode(editor, modes.textObject)
	return to
end

local function pushModeInsert(editor)
	if modes == nil then
		modes = require("vim.modes")
	end
	runMode(editor, modes.insertMode)
	performCursorMotion(editor, textObjects.characterBackward)
end

function registerValueFromText(editor, txt, protoRegValue)
	local regValue = {}
	if protoRegValue ~= nil then
		itertools.update(regValue, protoRegValue)
	end
	regValue.lines = itertools.collect(ipairs(txt))
	return regValue
end

runMode = function(editor, cb)
	local oldModeMappings = editor.typeahead:getModeMappings()
	local oldLangMappings = editor.typeahead:getLangMappings()
	local oldModeMessagge = editor:getModeMessage()
	local result = table.pack(xpcall(cb, debug.traceback, editor))
	editor.typeahead:setModeMappings(oldModeMappings)
	editor.typeahead:setLangMappings(oldLangMappings)
	editor:setModeMessage(oldModeMessagge)
	editor:render()
	if result[1] then
		return table.unpack(result, 2, result.n)
	else
		error(table.unpack(result, 2, result.n))
	end
end

local function scrollBy(editor, dx, dy, opts)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local cursorToCtx = makeMotionContext(editor)
	if cursorToCtx == nil then
		return
	end

	local scrollX, scrollY = win:getScrollAmount()
	scrollX = scrollX + dx
	scrollY = scrollY + dy
	win:setScrollAmount(scrollX, scrollY)
	local contentWidth, contentHeight = win:getContentSize()
	local cursorWindowX = cursorToCtx.x - scrollX
	local cursorWindowY = cursorToCtx.y - scrollY

	if cursorWindowX > contentWidth then
		cursorToCtx.x = cursorToCtx.x - cursorWindowX + contentWidth
		cursorToCtx.wantX = nil
	elseif cursorWindowX < 1 then
		cursorToCtx.x = cursorToCtx.x - cursorWindowX + 1
		cursorToCtx.wantX = nil
	end
	if cursorWindowY > contentHeight then
		cursorToCtx.y = cursorToCtx.y - cursorWindowY + contentHeight
	elseif cursorWindowY < 1 then
		cursorToCtx.y = cursorToCtx.y - cursorWindowY + 1
	end

	motionContextIntoBounds(editor, cursorToCtx, opts)
	scrollToMotionContextEnd(editor, cursorToCtx)
	updateCursorFromMotionContext(editor, cursorToCtx)
end

function scrollToMotionContextEnd(editor, toCtx)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end

	local scrollX, scrollY = win:getScrollAmount()
	local contentWidth, contentHeight = win:getContentSize()

	local cursorWindowX = toCtx.x - scrollX
	local cursorWindowY = toCtx.y - scrollY
	if cursorWindowX > contentWidth then
		scrollX = scrollX + cursorWindowX - contentWidth
	elseif cursorWindowX < 1 then
		scrollX = scrollX + cursorWindowX - 1
	end
	if scrollX < 0 then
		scrollX = 0
	end
	if cursorWindowY > contentHeight then
		scrollY = scrollY + cursorWindowY - contentHeight
	elseif cursorWindowY < 1 then
		scrollY = scrollY + cursorWindowY - 1
	end
	if scrollY < 0 then
		scrollY = 0
	end

	win:setScrollAmount(scrollX, scrollY)
end

local function setLastSelection(editor, to)
	-- TODO
end

local function setRepeatCount(editor, num)
	-- TODO better interface
	editor._repeatCount = num
end

local function setSelectedRegister(editor, regValue, opts)
	-- TODO registers
	editor._unnamedRegister = regValue
end

function setTextObjectAsRegister(editor, to, regValue)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local txt = regValue.lines
	if regValue.linewise then
		txt = itertools.collect(ipairs(txt))
		if isEmptyTextObject(editor, to) and to.x > 0 then
			table.insert(txt, 1, "")
		else
			table.insert(txt, "")
		end
	end
	buf:setTextBetween(txt, getTextObjectEnds(editor, to))
end

function updateCursorFromMotionContext(editor, toCtx)
	-- TODO cursor
	editor._cursorX = toCtx.x
	editor._cursorY = toCtx.y
	editor._cursorWantX = toCtx.wantX
end

textObjects = {
	characterForward = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.x = toCtx.x + getRepeatCount1(editor)
		local line = buf:getLine(toCtx.y)
		local lineLength = sysencoding.len(line)
		if toCtx.x > lineLength + 1 then
		    toCtx.x = lineLength + 1
		end
		toCtx.wantX = nil
		return toCtx
	end},
	characterBackward = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.x = toCtx.x - getRepeatCount1(editor)
		if toCtx.x < 1 then
			toCtx.x = 1
		end
		toCtx.wantX = nil
		return toCtx
	end},
	emptyForward = {{empty = true}, function(editor, toCtx)
		-- TODO consider using a simple exclusive motion with matching start and end instead
		toCtx.initialY = toCtx.y
		toCtx.initialX = toCtx.x + 1
		return toCtx
	end},
	emptyBackward = {{empty = true}, function(editor, toCtx)
		toCtx.y = toCtx.initialY
		toCtx.x = toCtx.initialX - 1
		return toCtx
	end},
	eol = {{exclusive = false}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.y = toCtx.y + getRepeatCount1(editor) - 1
		local numLines = buf:getLineCount()
		if toCtx.y > numLines then
		    toCtx.y = numLines
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = sysencoding.len(line)
		toCtx.x = lineLength + 1
		toCtx.wantX = nil
		return toCtx
	end},
	sol = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.y = toCtx.y - getRepeatCount1(editor) + 1  -- It is not possible to provide count to "0"
		if toCtx.y < 1 then
			toCtx.y = 1
		end
		toCtx.x = 1
		toCtx.wantX = nil
		return toCtx
	end},
	solNonSpace = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.y = toCtx.y - getRepeatCount1(editor) + 1  -- Real Vim doesn't accept count for "^"
		if toCtx.y < 1 then
			toCtx.y = 1
		end
		local line = buf:getLine(toCtx.y)
		toCtx.x = strptn.firstNonSpace(line) or sysencoding.len(line) + 1
		toCtx.wantX = nil
		return toCtx
	end},
	line = {{linewise = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.wantX ~= nil then
		    toCtx.x = toCtx.wantX
		else
		    toCtx.wantX = toCtx.x
		end
		toCtx.y = toCtx.y + getRepeatCount1(editor) - 1
		local numLines = buf:getLineCount()
		if toCtx.y > numLines then
		    toCtx.y = numLines
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = sysencoding.len(line)
		if toCtx.x > lineLength + 1 then  -- do we need "lineLength + 1" in any text objects?
		    toCtx.x = lineLength + 1
		end
		return toCtx
	end},
}

return {
	appendTextAtBuffer = appendTextAtBuffer,
	appendTextAt = appendTextAt,
	applyMotionToContext = applyMotionToContext,
	applyOperator = applyOperator,
	emptyRegisterValue = emptyRegisterValue,
	evaluateTextObject = evaluateTextObject,
	expandPaste = expandPaste,
	finalizeMotion = finalizeMotion,
	findCharacterInLine = findCharacterInLine,
	findWordInLine = findWordInLine,
	getRegisterValueText = getRegisterValueText,
	getRepeatCount0 = getRepeatCount0,
	getRepeatCount1 = getRepeatCount1,
	getSelectedRegister = getSelectedRegister,
	getTextObjectAsRegister = getTextObjectAsRegister,
	getTextObjectEnds = getTextObjectEnds,
	insertTextAtCursor = insertTextAtCursor,
	isEmptyTextObject = isEmptyTextObject,
	makeMotionContext = makeMotionContext,
	motionContextIntoBounds = motionContextIntoBounds,
	performCursorMotion = performCursorMotion,
	performWordMotion = performWordMotion,
	pullCountString = pullCountString,
	pullInputCharacter = pullInputCharacter,
	pullTextObject = pullTextObject,
	pushModeInsert = pushModeInsert,
	registerValueFromText = registerValueFromText,
	runMode = runMode,
	scrollBy = scrollBy,
	scrollToMotionContextEnd = scrollToMotionContextEnd,
	setLastSelection = setLastSelection,
	setRepeatCount = setRepeatCount,
	setSelectedRegister = setSelectedRegister,
	setTextObjectAsRegister = setTextObjectAsRegister,
	textObjects = textObjects,
	updateCursorFromMotionContext = updateCursorFromMotionContext,
}
