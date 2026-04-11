local helpers = require("vim.helpers")
local Trie = require("vim.trie")
local safeencoding = require("vim.safeencoding")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")
local keyseq = require("vim.keyseq")
local typeahead = require("vim.typeahead")
local math = require("math")
local strptn = require("vim.strptn")

local simpleOperators = {
	y = function(editor, to)
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		helpers.setSelectedRegister(editor, regValue, {yank = true})
	end,
	d = function(editor, to)
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		helpers.setSelectedRegister(editor, regValue, {delete = true})
		helpers.setTextObjectAsRegister(editor, to, helpers.emptyRegisterValue)
	end,
	c = function(editor, to)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		helpers.setSelectedRegister(editor, regValue, {delete = true})
		local emptyValue = helpers.emptyRegisterValue
		if to.linewise then
			local minY, maxY = to.initialY, to.y
			local numLines = buf:getLineCount()
			if minY > maxY then
				minY, maxY = maxY, minY
			end
			-- Don't validate maxY, as it is unused
			if minY > numLines then
				minY = numLines
			end
			if minY < 1 then
				minY = 1
			end
			local line = buf:getLine(minY)
			local indentLen = (strptn.firstNonSpace(line) or safeencoding.len(line) + 1) - 1
			local indent = safeencoding.sub(line, 1, indentLen)
			local txt = {indent}
			emptyValue = helpers.registerValueFromText(editor, txt, regValue)
		end
		helpers.setTextObjectAsRegister(editor, to, emptyValue)
		helpers.pushModeInsert(editor)
	end,
}

local pasteOperator = function(editor, to)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local oldRegValue = helpers.getSelectedRegister(editor)
	if not helpers.isEmptyTextObject(editor, to) then
		local newRegValue = helpers.getTextObjectAsRegister(editor, to)
		if newRegValue == nil then
			return
		end
		helpers.setSelectedRegister(editor, newRegValue, {delete = true})
	elseif oldRegValue.linewise then
		-- With an empty text object, a linewise register should perform linewise paste
		-- FIXME consider less dirty solution
		local cursorToCtx = helpers.makeMotionContext(editor)
		if to.x < cursorToCtx.x then  -- "P"
			to.initialX = 1
			to.x = 0
		else  -- "p"
			local line = buf:getLine(to.y)
			local lineLen = safeencoding.len(line)
			to.initialX = lineLen + 1
			to.x = lineLen
		end
	end
	-- TODO repetition
	local yieldCounter = 0
	for _ = 1, helpers.getRepeatCount1(editor) do
		helpers.setTextObjectAsRegister(editor, to, oldRegValue)
		yieldCounter = yieldCounter + 1
		if yieldCounter > 10 then
			yieldCounter = 0
			editor.typeahead:yieldCPU()
		end
		if not editor:notInterrupted() then
			return
		end
	end
end

local function clipboardPasteOperator(editor, to)
	local oldReg = helpers.getSelectedRegister(editor)
	local newReg = helpers.getPasteDataAsRegister(editor)
	if not newReg then
		return
	end
	helpers.setSelectedRegister(editor, newReg)
	pasteOperator(editor, to)
	helpers.setSelectedRegister(editor, oldReg)
end

local impendingOperators = {  -- don't trigger operator-pending mode when used from normal mode
	x = {helpers.textObjects.characterForward, simpleOperators.d},
	X = {helpers.textObjects.characterBackward, simpleOperators.d},
	p = {helpers.textObjects.emptyForward, pasteOperator},
	P = {helpers.textObjects.emptyBackward, pasteOperator},
	['"+p'] = {helpers.textObjects.emptyForward, clipboardPasteOperator},
	['"+P'] = {helpers.textObjects.emptyBackward, clipboardPasteOperator},
	Y = {helpers.textObjects.eol, simpleOperators.y},  -- Not Vi-compatible
	C = {helpers.textObjects.eol, simpleOperators.c},
	D = {helpers.textObjects.eol, simpleOperators.d},
	r = {helpers.textObjects.characterForward, function(editor, to)
		local ch = helpers.pullInputCharacter(editor)
		if not ch then
			return
		end
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		local oldTxt = helpers.getRegisterValueText(editor, regValue)
		local newTxt = {}
		for i, oldLine in ipairs(oldTxt) do
			local lineLen = safeencoding.len(oldLine)
			newTxt[i] = itertools.repeatString(ch, lineLen)
		end
		regValue = helpers.registerValueFromText(editor, newTxt, regValue)
		helpers.setTextObjectAsRegister(editor, to, regValue)
	end},
	gJ = {helpers.textObjects.multipleLines, function(editor, to)
		-- FIXME doesn't work in visual mode if only one line is selected
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		local oldTxt = helpers.getRegisterValueText(editor, regValue)
		local newTxt = {""}
		for _, oldLine in ipairs(oldTxt) do
			newTxt[1] = newTxt[1] .. oldLine
		end
		regValue = helpers.registerValueFromText(editor, newTxt, regValue)
		helpers.setTextObjectAsRegister(editor, to, regValue)
	end},
	J = {helpers.textObjects.multipleLines, function(editor, to)
		-- FIXME doesn't work in visual mode if only one line is selected
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		local oldTxt = helpers.getRegisterValueText(editor, regValue)
		local newTxt = {""}
		for i, oldLine in ipairs(oldTxt) do
			if i > 1 then
				local indentLen = (strptn.firstNonSpace(oldLine) or safeencoding.len(oldLine) + 1) - 1
				oldLine = " " .. safeencoding.sub(oldLine, indentLen + 1)
			end
			newTxt[1] = newTxt[1] .. oldLine
		end
		regValue = helpers.registerValueFromText(editor, newTxt, regValue)
		helpers.setTextObjectAsRegister(editor, to, regValue)
	end},
}

local impendingNormalOperators = {  -- don't exist in visual mode
	yy = {helpers.textObjects.line, simpleOperators.y},
	cc = {helpers.textObjects.line, simpleOperators.c},
	dd = {helpers.textObjects.line, simpleOperators.d},
}

local simpleMotions
simpleMotions = {
	h = helpers.textObjects.characterBackward,
	j = {{}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.linewise == nil then  -- preserve false
		    toCtx.linewise = true
		end
		if toCtx.wantX ~= nil then
		    toCtx.x = toCtx.wantX
		else
		    toCtx.wantX = toCtx.x
		end
		toCtx.y = toCtx.y + helpers.getRepeatCount1(editor)
		local numLines = buf:getLineCount()
		if toCtx.y > numLines then
		    toCtx.y = numLines
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = safeencoding.len(line)
		if toCtx.x > lineLength + 1 then
		    toCtx.x = lineLength + 1
		end
		return toCtx
	end},
	k = {{}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.linewise == nil then  -- preserve false
		    toCtx.linewise = true
		end
		if toCtx.wantX ~= nil then
		    toCtx.x = toCtx.wantX
		else
		    toCtx.wantX = toCtx.x
		end
		toCtx.y = toCtx.y - helpers.getRepeatCount1(editor)
		if toCtx.y < 1 then
			toCtx.y = 1
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = safeencoding.len(line)
		if toCtx.x > lineLength + 1 then
		    toCtx.x = lineLength + 1
		end
		return toCtx
	end},
	l = helpers.textObjects.characterForward,
	f = {{}, function(editor, toCtx)
		local ch = helpers.pullInputCharacter(editor)
		if not ch then
			return toCtx
		end
		-- TODO better interface
		editor._lastCharSearch = {"f", ch}
		local newX = helpers.findCharacterInLine(editor, ch, toCtx, {backward = false, count = helpers.getRepeatCount1(editor)})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
		end
		return toCtx
	end},
	t = {{}, function(editor, toCtx)
		local ch = helpers.pullInputCharacter(editor)
		if not ch then
			return toCtx
		end
		-- TODO better interface
		editor._lastCharSearch = {"t", ch}
		toCtx.x = toCtx.x + 1
		local newX = helpers.findCharacterInLine(editor, ch, toCtx, {backward = false, count = helpers.getRepeatCount1(editor)})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
		end
		toCtx.x = toCtx.x - 1
		return toCtx
	end},
	F = {{exclusive = true}, function(editor, toCtx)
		local ch = helpers.pullInputCharacter(editor)
		if not ch then
			return toCtx
		end
		-- TODO better interface
		editor._lastCharSearch = {"F", ch}
		local newX = helpers.findCharacterInLine(editor, ch, toCtx, {backward = true, count = helpers.getRepeatCount1(editor)})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
		end
		return toCtx
	end},
	T = {{exclusive = true}, function(editor, toCtx)
		local ch = helpers.pullInputCharacter(editor)
		if not ch then
			return toCtx
		end
		-- TODO better interface
		editor._lastCharSearch = {"T", ch}
		toCtx.x = toCtx.x - 1
		local newX = helpers.findCharacterInLine(editor, ch, toCtx, {backward = true, count = helpers.getRepeatCount1(editor)})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
		end
		toCtx.x = toCtx.x + 1
		return toCtx
	end},
	[";"] = {{}, function(editor, toCtx)
		-- TODO better interface
		local last = editor._lastCharSearch
		if last == nil then
			return toCtx
		end
		editor._lastCharSearch = nil
		editor.typeahead:insert(last[2], {index = 1, noModeMap = true, noLangMap = true})
		local kind = last[1]
		local mot = simpleMotions[kind]
		itertools.update(toCtx, mot[1])
		toCtx = mot[2](editor, toCtx)
		editor._lastCharSearch = last
		return toCtx
	end},
	[","] = {{}, function(editor, toCtx)
		-- TODO better interface
		local last = editor._lastCharSearch
		if last == nil then
			return toCtx
		end
		editor._lastCharSearch = nil
		editor.typeahead:insert(last[2], {index = 1, noModeMap = true, noLangMap = true})
		local kind = ({f = "F", t = "T", F = "f", T = "t"})[last[1]]
		local mot = simpleMotions[kind]
		itertools.update(toCtx, mot[1])
		toCtx = mot[2](editor, toCtx)
		editor._lastCharSearch = last
		return toCtx
	end},
	w = {{exclusive = true}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = false, wordEnd = false, WORDs = false})
	end},
	W = {{exclusive = true}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = false, wordEnd = false, WORDs = true})
	end},
	b = {{exclusive = true}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = true, wordEnd = false, WORDs = false})
	end},
	B = {{exclusive = true}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = true, wordEnd = false, WORDs = true})
	end},
	e = {{}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = false, wordEnd = true, WORDs = false})
	end},
	E = {{}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = false, wordEnd = true, WORDs = true})
	end},
	ge = {{}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = true, wordEnd = true, WORDs = false})
	end},
	gE = {{}, function(editor, toCtx)
		return helpers.performWordMotion(editor, toCtx, {backward = true, wordEnd = true, WORDs = true})
	end},
	["0"] = helpers.textObjects.sol,
	["^"] = helpers.textObjects.solNonSpace,
	["$"] = helpers.textObjects.eol,
	gg = {{}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.linewise == nil then  -- preserve false
			toCtx.linewise = true
		end
		toCtx.y = helpers.getRepeatCount1(editor)
		helpers.motionContextIntoBounds(editor, toCtx)
		local line = buf:getLine(toCtx.y)
		toCtx.x = strptn.firstNonSpace(line) or safeencoding.len(line) + 1
		toCtx.wantX = nil
		return toCtx
	end},
	G = {{}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.linewise == nil then  -- preserve false
			toCtx.linewise = true
		end
		local n = helpers.getRepeatCount0(editor)
		if n < 1 then
			n = buf:getLineCount()
		end
		toCtx.y = n
		helpers.motionContextIntoBounds(editor, toCtx)
		local line = buf:getLine(toCtx.y)
		toCtx.x = strptn.firstNonSpace(line) or safeencoding.len(line) + 1
		toCtx.wantX = nil
		return toCtx
	end},
	["/"] = {{exclusive = true}, function(editor, toCtx)
		local searchString = helpers.pullSearchString(editor, false)
		if not searchString then
			return toCtx
		end
		helpers.setSearchString(editor, searchString)
		helpers.setSearchBackward(editor, false)
		editor.hlsearch = editor.triggerHlsearch
		editor:invalidateDisplay()
		return helpers.performSearchMotion(editor, toCtx)
	end},
	["?"] = {{exclusive = true}, function(editor, toCtx)
		local searchString = helpers.pullSearchString(editor, true)
		if not searchString then
			return toCtx
		end
		helpers.setSearchString(editor, searchString)
		helpers.setSearchBackward(editor, true)
		editor.hlsearch = editor.triggerHlsearch
		editor:invalidateDisplay()
		return helpers.performSearchMotion(editor, toCtx)
	end},
	n = helpers.textObjects.searchNext,
	N = helpers.textObjects.searchPrevious,
}

local simpleNonprintMotions = {
	["<left>"] = simpleMotions.h,
	["<down>"] = simpleMotions.j,
	["<up>"] = simpleMotions.k,
	["<right>"] = simpleMotions.l,
	["<home>"] = simpleMotions["0"],
	["<end>"] = simpleMotions["$"],
	["<leftmouse>"] = {{exclusive = true}, helpers.performMouseMotion},
	["<rightmouse>"] = {{exclusive = false}, helpers.performMouseMotion},
}

local textObjectMotions = {
	["iw"] = {{exclusive = false, linewise = false}, function(editor, toCtx)
		-- TODO count
		local backward = toCtx.y < toCtx.initialY or toCtx.y == toCtx.initialY and toCtx.x < toCtx.initialX
		local m = helpers.findSurroundingWordInLine(editor, toCtx, {WORDs = false})
		if not m then
			return toCtx
		end
		if backward then
			toCtx.x = m[1]
			if toCtx.y == toCtx.initialY and toCtx.initialX < m[2] then
				toCtx.initialX = m[2]
			end
		else
			toCtx.x = m[2]
			if toCtx.y == toCtx.initialY and toCtx.initialX > m[1] then
				toCtx.initialX = m[1]
			end
		end
		return toCtx
	end},
	["iW"] = {{exclusive = false, linewise = false}, function(editor, toCtx)
		-- TODO count
		local backward = toCtx.y < toCtx.initialY or toCtx.y == toCtx.initialY and toCtx.x < toCtx.initialX
		local m = helpers.findSurroundingWordInLine(editor, toCtx, {WORDs = true})
		if not m then
			return toCtx
		end
		if backward then
			toCtx.x = m[1]
			if toCtx.y == toCtx.initialY and toCtx.initialX < m[2] then
				toCtx.initialX = m[2]
			end
		else
			toCtx.x = m[2]
			if toCtx.y == toCtx.initialY and toCtx.initialX > m[1] then
				toCtx.initialX = m[1]
			end
		end
		return toCtx
	end},
}

local scrollActions = {  -- similar to motions, but don't exist in operator-pending mode
	["<C-y>"] = function(editor, opts)
		helpers.scrollBy(editor, 0, -helpers.getRepeatCount1(editor), opts)
	end,
	["<C-e>"] = function(editor, opts)
		helpers.scrollBy(editor, 0,  helpers.getRepeatCount1(editor), opts)
	end,
	["<C-b>"] = function(editor, opts)
		local win = editor:getCurrentWindow()
		if win == nil then
			return
		end
		local contentWidth, contentHeight = win:getContentSize()
		local multiplier = contentHeight - 2
		if multiplier < 1 then
			multiplier = 1
		end
		local amount = multiplier * helpers.getRepeatCount1(editor) + 2
		helpers.scrollBy(editor, 0, -amount, opts)
	end,
	["<C-f>"] = function(editor, opts)
		local win = editor:getCurrentWindow()
		if win == nil then
			return
		end
		local contentWidth, contentHeight = win:getContentSize()
		local multiplier = contentHeight - 2
		if multiplier < 1 then
			multiplier = 1
		end
		local amount = multiplier * helpers.getRepeatCount1(editor) + 2
		helpers.scrollBy(editor, 0,  amount, opts)
	end,
	["<C-u>"] = function(editor, opts)
		local scrollOption = helpers.getRepeatCount0(editor)
		if scrollOption ~= 0 then
			-- TODO better interface
			editor._scrollOption = scrollOption
		else
			scrollOption = editor._scrollOption
		end
		helpers.scrollBy(editor, 0, -scrollOption, opts)
	end,
	["<C-d>"] = function(editor, opts)
		local scrollOption = helpers.getRepeatCount0(editor)
		if scrollOption ~= 0 then
			-- TODO better interface
			editor._scrollOption = scrollOption
		else
			scrollOption = editor._scrollOption
		end
		helpers.scrollBy(editor, 0,  scrollOption, opts)
	end,
	["zh"] = function(editor, opts)
		helpers.scrollBy(editor, -helpers.getRepeatCount1(editor), 0, opts)
	end,
	["zl"] = function(editor, opts)
		helpers.scrollBy(editor,  helpers.getRepeatCount1(editor), 0, opts)
	end,
	["zH"] = function(editor, opts)
		local win = editor:getCurrentWindow()
		if win == nil then
			return
		end
		local contentWidth, contentHeight = win:getContentSize()
		local multiplier = math.floor(contentWidth / 2) - 1
		if multiplier < 1 then
			multiplier = 1
		end
		local amount = multiplier * helpers.getRepeatCount1(editor) + 2
		helpers.scrollBy(editor, -amount, 0, opts)
	end,
	["zL"] = function(editor, opts)
		local win = editor:getCurrentWindow()
		if win == nil then
			return
		end
		local contentWidth, contentHeight = win:getContentSize()
		local multiplier = math.floor(contentWidth / 2) - 1
		if multiplier < 1 then
			multiplier = 1
		end
		local amount = multiplier * helpers.getRepeatCount1(editor) + 2
		helpers.scrollBy(editor,  amount, 0, opts)
	end,
}

local scrollNonprintActions = {
	["<scrollwheelup>"] = function(editor, opts)
		helpers.scrollBy(editor, 0, -3 * helpers.getRepeatCount1(editor), opts)
	end,
	["<scrollwheeldown>"] = function(editor, opts)
		helpers.scrollBy(editor, 0,  3 * helpers.getRepeatCount1(editor), opts)
	end,
	["<scrollwheelleft>"] = function(editor, opts)
		helpers.scrollBy(editor, -3 * helpers.getRepeatCount1(editor), 0, opts)
	end,
	["<scrollwheelright>"] = function(editor, opts)
		helpers.scrollBy(editor,  3 * helpers.getRepeatCount1(editor), 0, opts)
	end,
	["<pageup>"] = scrollActions["<C-b>"],
	["<pagedown>"] = scrollActions["<C-f>"],
	["<S-scrollwheelup>"] = scrollActions["<C-b>"],
	["<S-scrollwheeldown>"] = scrollActions["<C-f>"],
	["<S-scrollwheelleft>"] = function(editor, opts)
		local win = editor:getCurrentWindow()
		if win == nil then
			return
		end
		local contentWidth, contentHeight = win:getContentSize()
		local multiplier = contentWidth - 2
		if multiplier < 1 then
			multiplier = 1
		end
		local amount = multiplier * helpers.getRepeatCount1(editor) + 2
		helpers.scrollBy(editor, -amount, 0, opts)
	end,
	["<S-scrollwheelright>"] = function(editor, opts)
		local win = editor:getCurrentWindow()
		if win == nil then
			return
		end
		local contentWidth, contentHeight = win:getContentSize()
		local multiplier = contentWidth - 2
		if multiplier < 1 then
			multiplier = 1
		end
		local amount = multiplier * helpers.getRepeatCount1(editor) + 2
		helpers.scrollBy(editor,  amount, 0, opts)
	end,
}

local normalActions = {
	ZQ = function(editor)
		editor:terminate()
	end,
	i = function(editor)
		helpers.pushModeInsert(editor)
	end,
	a = function(editor)
		local repeatCount = helpers.getRepeatCount0(editor)
		helpers.setRepeatCount(editor, 0)
		helpers.performCursorMotion(editor, helpers.textObjects.characterForward, {onePastEnd = true})
		helpers.setRepeatCount(editor, repeatCount)
		helpers.pushModeInsert(editor)
	end,
	I = function(editor)
		helpers.performCursorMotion(editor, helpers.textObjects.solNonSpace, {onePastEnd = true})
		helpers.pushModeInsert(editor)
	end,
	A = function(editor)
		helpers.performCursorMotion(editor, helpers.textObjects.eol, {onePastEnd = true})
		helpers.pushModeInsert(editor)
	end,
	["@+"] = function(editor)
		helpers.expandPaste(editor)
		return false
	end,
	o = function(editor)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local cursorToCtx = helpers.makeMotionContext(editor)
		local line = buf:getLine(cursorToCtx.y)
		local indentLen = (strptn.firstNonSpace(line) or safeencoding.len(line) + 1) - 1
		local indent = safeencoding.sub(line, 1, indentLen)
		local repeatCount = helpers.getRepeatCount0(editor)
		helpers.setRepeatCount(editor, 0)
		helpers.performCursorMotion(editor, helpers.textObjects.eol, {onePastEnd = true})
		helpers.setRepeatCount(editor, repeatCount)
		local cursorTo = helpers.makeFinalizedEmptyCursorMotion(editor)
		local change = buf:startStagingChange(helpers.getTextObjectEnds(editor, cursorTo))
		table.insert(buf.insertStagingStack, change)
		helpers.insertTextAtCursor(editor, {"", indent})
		table.remove(buf.insertStagingStack)
		editor:render()
		helpers.pushModeInsert(editor, change)
	end,
	O = function(editor)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local cursorToCtx = helpers.makeMotionContext(editor)
		local line = buf:getLine(cursorToCtx.y)
		local indentLen = (strptn.firstNonSpace(line) or safeencoding.len(line) + 1) - 1
		local indent = safeencoding.sub(line, 1, indentLen)
		local repeatCount = helpers.getRepeatCount0(editor)
		helpers.setRepeatCount(editor, 0)
		helpers.performCursorMotion(editor, helpers.textObjects.sol)
		helpers.setRepeatCount(editor, repeatCount)
		local cursorTo = helpers.makeFinalizedEmptyCursorMotion(editor)
		local change = buf:startStagingChange(helpers.getTextObjectEnds(editor, cursorTo))
		table.insert(buf.insertStagingStack, change)
		helpers.insertTextAtCursor(editor, {indent, ""})
		table.remove(buf.insertStagingStack)
		cursorToCtx = helpers.makeMotionContext(editor)
		cursorToCtx.y = cursorToCtx.y - 1
		cursorToCtx.x = indentLen + 1
		helpers.updateCursorFromMotionContext(editor, cursorToCtx)
		editor:render()
		helpers.pushModeInsert(editor, change)
		-- FIXME cursor jumps somewhere in the next line after finishing
	end,
	v = function(editor)
		helpers.pushModeVisual(editor)
	end,
	V = function(editor)
		local toCtx = helpers.makeMotionContext(editor)
		toCtx.linewise = true
		helpers.pushModeVisual(editor, toCtx)
	end,
	gv = function(editor)
		local toCtx = helpers.restoreSelectionMotionContext(editor)
		helpers.pushModeVisual(editor, toCtx)
	end,
	[":"] = function(editor)
		helpers.pushModeCommandLine(editor)
	end,
	u = function(editor)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local n = 0
		for _ = 1, helpers.getRepeatCount1(editor) do
			if buf:undo() then
				n = n + 1
			else
				break
			end
		end
		if n > 0 then
			local cursorToCtx = helpers.makeMotionContext(editor)
			if cursorToCtx then
				helpers.motionContextIntoBounds(editor, cursorToCtx, opts)  -- TODO expose undo position instead
				helpers.scrollToMotionContextEnd(editor, cursorToCtx)
				helpers.updateCursorFromMotionContext(editor, cursorToCtx)
			end
			editor:echo(string.format("Undone %d changes", n))
		end
	end,
	["<C-r>"] = function(editor)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local n = 0
		for _ = 1, helpers.getRepeatCount1(editor) do
			if buf:redo() then
				n = n + 1
			else
				break
			end
		end
		if n > 0 then
			local cursorToCtx = helpers.makeMotionContext(editor)
			if cursorToCtx then
				helpers.motionContextIntoBounds(editor, cursorToCtx, opts)  -- TODO expose undo position instead
				helpers.scrollToMotionContextEnd(editor, cursorToCtx)
				helpers.updateCursorFromMotionContext(editor, cursorToCtx)
			end
			editor:echo(string.format("Redone %d changes", n))
		end
	end,
	["<rightmouse>"] = function(editor)
		local toCtx = helpers.makeMotionContext(editor)
		helpers.performMouseMotion(editor, toCtx)
		helpers.pushModeVisual(editor, toCtx)
	end,
	ga = function(editor)
		editor:echo(helpers.formatCharsInfo(editor, helpers.getCursorGrapheme(editor)))
	end,
}

local insertActions = {
	["<tab>"] = function(editor, change)
		return true
	end,
	["<space>"] = function(editor, change)
		helpers.insertTextAtCursor(editor, {" "})
		return false
	end,
	["<cr>"] = function(editor, change)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local indent = ""
		if not editor.typeahead:wasLastPasted() then
			local cursorToCtx = helpers.makeMotionContext(editor)
			local line = buf:getLine(cursorToCtx.y)
			local indentLen = (strptn.firstNonSpace(line) or safeencoding.len(line) + 1) - 1
			indent = safeencoding.sub(line, 1, indentLen)
		end
		helpers.insertTextAtCursor(editor, {"", indent})
		return false
	end,
	["<bs>"] = function(editor, change)
		local toCtx = helpers.makeMotionContext(editor)
		if toCtx == nil then
			return true
		end
		toCtx.exclusive = true
		if toCtx.x > 1 then
			toCtx.x = toCtx.x - 1
		elseif toCtx.y > 1 then
			toCtx.y = toCtx.y - 1
			local buf = editor:getCurrentBuffer()
			if buf == nil then
				return true
			end
			local line = buf:getLine(toCtx.y)
			toCtx.x = safeencoding.len(line) + 1
		else
			return false
		end
		local to = helpers.finalizeMotion(editor, toCtx)
		helpers.setTextObjectAsRegister(editor, to, helpers.emptyRegisterValue)
		helpers.updateCursorFromMotionContext(editor, toCtx)
		return false
	end,
	["<C-r>+"] = function(editor, change)
		helpers.expandPaste(editor, {noModeMap = true, noLangMap = true})
		return false
	end,
	["<S-insert>"] = function(editor, change)
		helpers.insertTextAtCursor(editor, helpers.getRegisterValueText(editor, helpers.getPasteDataAsRegister(editor)))
		return false
	end,
	["<C-v>x"] = function(editor, change)
		local charCode = 0
		for _ = 1, 2 do
			local nibbleNum = helpers.pullHexDigit(editor)
			if not nibbleNum then
				return false
			end
			charCode = charCode * 16 + nibbleNum
		end
		ch = string.char(charCode)
		if ch == "\n" then
			helpers.insertTextAtCursor(editor, {"", ""})
		else
			helpers.insertTextAtCursor(editor, {ch})
		end
		return false
	end,
	["<C-v>u"] = function(editor, change)
		local charCode = 0
		for _ = 1, 4 do
			local nibbleNum = helpers.pullHexDigit(editor)
			if not nibbleNum then
				return false
			end
			charCode = charCode * 16 + nibbleNum
		end
		ch = sysencoding.fromCodePoint(charCode)
		if not ch then
			return false
		end
		if ch == "\n" then
			helpers.insertTextAtCursor(editor, {"", ""})
		else
			helpers.insertTextAtCursor(editor, {ch})
		end
		return false
	end,
}

local visualActions = {
	["<tab>"] = function(editor, toCtx)
		local to = helpers.finalizeMotion(editor, toCtx)
		helpers.setLastSelection(editor, to)
		return true, toCtx
	end,
	v = function(editor, toCtx)
		if toCtx.linewise then
			toCtx.linewise = false
			return false, toCtx
		end
		return true, toCtx
	end,
	V = function(editor, toCtx)
		if not toCtx.linewise then
			toCtx.linewise = true
			return false, toCtx
		end
		return true, toCtx
	end,
	o = function(editor, toCtx)
		toCtx.x, toCtx.initialX = toCtx.initialX, toCtx.x
		toCtx.y, toCtx.initialY = toCtx.initialY, toCtx.y
		toCtx.wantX = nil
		return false, toCtx
	end,
	O = function(editor, toCtx)
		-- In actual Vim it behaves exactly like `o`, unless in blockwise mode
		toCtx.x, toCtx.initialX = toCtx.initialX, toCtx.x
		toCtx.wantX = nil
		return false, toCtx
	end,
	["<leftmouse>"] = function(editor, toCtx)
		local to = helpers.finalizeMotion(editor, toCtx)
		helpers.setLastSelection(editor, to)
		local cursorToCtx = helpers.makeMotionContext(editor)
		helpers.performMouseMotion(editor, cursorToCtx)
		helpers.motionContextIntoBounds(editor, cursorToCtx)
		helpers.scrollToMotionContextEnd(editor, cursorToCtx)
		helpers.updateCursorFromMotionContext(editor, cursorToCtx)
		return true, toCtx
	end,
	[":"] = function(editor, toCtx)
		local to = helpers.finalizeMotion(editor, toCtx)
		helpers.setLastSelection(editor, to)
		-- Ideally, this should run after the visual mode is popped (but before visual selection unrenders),
		-- But currently the only way to defer actions is prepending keys to typeahead,
		-- Which we generally try to minimize, and in this case would also depend on the following key being processed in the normal mode
		-- Which would break if we ever support `<c-o>v:` starting in the insert mode
		helpers.pushModeCommandLine(editor, {text = "'<,'>"})
		return true, toCtx
	end,
	ga = function(editor, toCtx)
		editor:echo(helpers.formatCharsInfo(editor, helpers.getCursorGrapheme(editor)))
		return false, toCtx
	end,
}

local cmdlineActions = {
	["<tab>"] = function(editor, state)
		state.finished = true
		state.text = nil
	end,
	["<cr>"] = function(editor, state)
		state.finished = true
	end,
	["<bs>"] = function(editor, state)
		local x = state.x
		if x < 2 then
			if #state.text < 1 then
				state.text = nil
				state.finished = true
			end
			return
		end
		state.text = safeencoding.sub(state.text, 1, x - 2) .. safeencoding.sub(state.text, x)
		state.x = x - 1
	end,
	["<left>"] = function(editor, state)
		local x = state.x
		if x < 2 then
			return
		end
		state.x = x - 1
	end,
	["<right>"] = function(editor, state)
		local text = state.text or ""
		local x = state.x
		if x > safeencoding.len(text) then
			return
		end
		state.x = x + 1
	end,
	["<S-up>"] = function(editor, state)
		if state.historyPos <= 1 then
			return
		end
		state.history[state.historyPos] = state.text
		state.historyPos = state.historyPos - 1
		state.text = state.history[state.historyPos]
		state.x = safeencoding.len(state.text) + 1
	end,
	["<S-down>"] = function(editor, state)
		if state.historyPos >= #state.history then
			return
		end
		state.history[state.historyPos] = state.text
		state.historyPos = state.historyPos + 1
		state.text = state.history[state.historyPos]
		state.x = safeencoding.len(state.text) + 1
	end,
	["<C-b>"] = function(editor, state)
		state.x = 1
	end,
	["<C-e>"] = function(editor, state)
		local text = state.text or ""
		state.x = safeencoding.len(text) + 1
	end,
	["<C-r>+"] = function(editor, state)
		helpers.expandPaste(editor, {noModeMap = true, noLangMap = true})
	end,
	["<C-r>/"] = function(editor, state)
		local x = state.x
		local searchString = helpers.getSearchString(editor)
		state.text = safeencoding.sub(state.text, 1, x - 1) .. searchString .. safeencoding.sub(state.text, x)
		state.x = x + safeencoding.len(searchString)
	end,
	["<C-v>x"] = function(editor, state)
		local charCode = 0
		for _ = 1, 2 do
			local nibbleNum = helpers.pullHexDigit(editor)
			if not nibbleNum then
				return
			end
			charCode = charCode * 16 + nibbleNum
		end
		ch = string.char(charCode)
		if ch == "\n" then
			return
		end

		local x = state.x
		state.text = safeencoding.sub(state.text, 1, x - 1) .. ch .. safeencoding.sub(state.text, x)
		state.x = x + safeencoding.len(ch)
	end,
	["<C-v>u"] = function(editor)
		local charCode = 0
		for _ = 1, 4 do
			local nibbleNum = helpers.pullHexDigit(editor)
			if not nibbleNum then
				return
			end
			charCode = charCode * 16 + nibbleNum
		end
		ch = sysencoding.fromCodePoint(charCode)
		if not ch then
			return
		end
		if ch == "\n" then
			return
		end

		local x = state.x
		state.text = safeencoding.sub(state.text, 1, x - 1) .. ch .. safeencoding.sub(state.text, x)
		state.x = x + safeencoding.len(ch)
	end,
}

-- Host client paste aliases (<insert> in OC and <C-v> in CC are used to trigger paste event)
normalActions["@<insert>"] = normalActions["@+"]  -- Interpret clipboard data as Vim controls!
normalActions["@<C-v>"] = normalActions["@+"]
insertActions["<C-r><insert>"] = insertActions["<C-r>+"]  -- Interpret clipboard data as inserted keys (almost like paste, but slow)
insertActions["<C-r><C-v>"] = insertActions["<C-r>+"]
cmdlineActions["<S-insert>"] = cmdlineActions["<C-r>+"]
cmdlineActions["<C-S-v>"] = cmdlineActions["<C-r>+"]
cmdlineActions["<C-r><insert>"] = cmdlineActions["<C-r>+"]
cmdlineActions["<C-r><C-v>"] = cmdlineActions["<C-r>+"]
impendingOperators['"<insert>p'] = impendingOperators['"+p']  -- Actually paste
impendingOperators['"<C-v>p'] = impendingOperators['"+p']
impendingOperators['"<insert>P'] = impendingOperators['"+P']
impendingOperators['"<C-v>P'] = impendingOperators['"+P']
impendingOperators["<S-insert>"] = impendingOperators['"+p']
impendingOperators["<C-S-v>"] = impendingOperators['"+p']
insertActions["<C-S-v>"] = insertActions["<S-insert>"]

-- TODO recall history by prefix
cmdlineActions["<up>"] = cmdlineActions["<S-up>"]
cmdlineActions["<down>"] = cmdlineActions["<S-down>"]
cmdlineActions["<home>"] = cmdlineActions["<C-b>"]
cmdlineActions["<end>"] = cmdlineActions["<C-e>"]

local function getOrNewTrie(tbl, name)
	local val = tbl[name]
	if val == nil then
		val = Trie()
		tbl[name] = val
	end
	return val
end

local function putAtKeySeq(trie, keyStr, value)
	local key = keyseq.parseKeySequence(keyStr, typeahead.keyNormalisation, typeahead.modifierOrder)
	trie:put(key, value)
end

local function makeNormalSimpleOperator(simpleOp)
	return function(editor)
		local to = helpers.pullTextObject(editor)
		if to == nil then
			return
		end
		return helpers.applyOperator(editor, simpleOp, to)
	end
end

local function makeNormalImpendingOperator(toDef, op)
	return function(editor)
		local to = helpers.evaluateTextObject(editor, toDef)
		if to == nil then
			return
		end
		return helpers.applyOperator(editor, op, to)
	end
end

local function makeNormalMotion(toDef)
	return function(editor)
		helpers.performCursorMotion(editor, toDef)
	end
end

local function makeVisualMotion(toDef)
	return function(editor, toCtx)
		toCtx = helpers.applyMotionToContext(editor, toCtx, toDef)
		if toCtx == nil then
			return nil
		end
		return false, toCtx
	end
end

local function makeVisualOperator(op)
	return function(editor, toCtx)
		local to = helpers.finalizeMotion(editor, toCtx)
		if to == nil then
			return nil
		end
		helpers.setLastSelection(editor, to)
		helpers.applyOperator(editor, op, to)
		return true
	end
end

local function makeVisualScrollAction(op)
	return function(editor, toCtx)
		helpers.updateCursorFromMotionContext(editor, toCtx)
		op(editor)
		local cursorToCtx = helpers.makeMotionContext(editor)
		toCtx.x = cursorToCtx.x
		toCtx.y = cursorToCtx.y
		toCtx.wantX = cursorToCtx.wantX
		return false, toCtx
	end
end

local function makeOperatorPendingMotion(toDef)
	return function(editor, toCtx)
		toCtx = helpers.applyMotionToContext(editor, toCtx, toDef)
		return toCtx
	end
end

local function makeInsertMotion(toDef)
	return function(editor, change)
		if not helpers.performCursorMotion(editor, toDef, {onePastEnd = true}) then
			return nil
		end
		return false
	end
end

local function makeInsertScrollAction(op)
	return function(editor, change)
		op(editor, {onePastEnd = true})
		return false
	end
end

local function initialize(modeTries)
	local normal = getOrNewTrie(modeTries, "normal")
	local visual = getOrNewTrie(modeTries, "visual")
	local textObject = getOrNewTrie(modeTries, "textObject")  -- a. k. a. operator-pending
	local select_ = getOrNewTrie(modeTries, "select")
	local insert = getOrNewTrie(modeTries, "insert")
	local cmdline = getOrNewTrie(modeTries, "cmdline")

	for seq, op in pairs(simpleOperators) do
		putAtKeySeq(normal, seq, makeNormalSimpleOperator(op))
		putAtKeySeq(visual, seq, makeVisualOperator(op))
	end

	for seq, op in pairs(impendingOperators) do
		putAtKeySeq(normal, seq, makeNormalImpendingOperator(op[1], op[2]))
		putAtKeySeq(visual, seq, makeVisualOperator(op[2]))
	end

	for seq, op in pairs(impendingNormalOperators) do
		putAtKeySeq(normal, seq, makeNormalImpendingOperator(op[1], op[2]))
	end

	for seq, mot in pairs(simpleMotions) do
		putAtKeySeq(normal, seq, makeNormalMotion(mot))
		putAtKeySeq(visual, seq, makeVisualMotion(mot))
		putAtKeySeq(textObject, seq, makeOperatorPendingMotion(mot))
	end

	for seq, mot in pairs(simpleNonprintMotions) do
		local visMot = makeVisualMotion(mot)
		putAtKeySeq(normal, seq, makeNormalMotion(mot))
		putAtKeySeq(visual, seq, visMot)
		putAtKeySeq(textObject, seq, makeOperatorPendingMotion(mot))
		putAtKeySeq(select_, seq, visMot)
		putAtKeySeq(insert, seq, makeInsertMotion(mot))
	end

	for seq, mot in pairs(textObjectMotions) do
		putAtKeySeq(visual, seq, makeVisualMotion(mot))
		putAtKeySeq(textObject, seq, makeOperatorPendingMotion(mot))
	end

	for seq, act in pairs(normalActions) do
		putAtKeySeq(normal, seq, act)
	end

	for seq, act in pairs(insertActions) do
		putAtKeySeq(insert, seq, act)
	end

	for seq, act in pairs(visualActions) do
		putAtKeySeq(visual, seq, act)
	end

	for seq, act in pairs(cmdlineActions) do
		putAtKeySeq(cmdline, seq, act)
	end

	for seq, act in pairs(scrollActions) do
		putAtKeySeq(normal, seq, act)
		putAtKeySeq(visual, seq, makeVisualScrollAction(act))
	end

	for seq, act in pairs(scrollNonprintActions) do
		putAtKeySeq(normal, seq, act)
		putAtKeySeq(visual, seq, makeVisualScrollAction(act))
		putAtKeySeq(insert, seq, makeInsertScrollAction(act))
	end
end

return {
	initialize = initialize,
}
