local helpers = require("vim.helpers")
local Trie = require("vim.trie")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")
local keyseq = require("vim.keyseq")
local typeahead = require("vim.typeahead")

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
		local regValue = helpers.getTextObjectAsRegister(editor, to)
		if regValue == nil then
			return
		end
		helpers.setSelectedRegister(editor, regValue, {delete = true})
		helpers.setTextObjectAsRegister(editor, to, helpers.emptyRegisterValue)
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
		-- FIXME line break is inserted at the wrong end of the pasted text half of the time
		local cursorToCtx = helpers.makeMotionContext(editor)
		if to.x < cursorToCtx.x then  -- "P"
			to.initialX = 1
			to.x = 0
		else  -- "p"
			local line = buf:getLine(to.y)
			local lineLen = sysencoding.len(line)
			to.initialX = lineLen + 1
			to.x = lineLen
		end
	end
	-- TODO repetition
	helpers.setTextObjectAsRegister(editor, to, oldRegValue)
end

local impendingOperators = {  -- don't trigger operator-pending mode when used from normal mode
	x = {helpers.textObjects.characterForward, simpleOperators.d},
	X = {helpers.textObjects.characterBackward, simpleOperators.d},
	p = {helpers.textObjects.emptyForward, pasteOperator},
	P = {helpers.textObjects.emptyBackward, pasteOperator},
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
			local lineLen = sysencoding.len(oldLine)
			newTxt[i] = itertools.repeatString(ch, lineLen)
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

local simpleMotions = {
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
		local lineLength = sysencoding.len(line)
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
		local lineLength = sysencoding.len(line)
		if toCtx.x > lineLength + 1 then
		    toCtx.x = lineLength + 1
		end
		return toCtx
	end},
	l = helpers.textObjects.characterForward,
}

local simpleNonprintMotions = {
	["<left>"] = simpleMotions.h,
	["<down>"] = simpleMotions.j,
	["<up>"] = simpleMotions.k,
	["<right>"] = simpleMotions.l,
	["<home>"] = simpleMotions["0"],
	["<end>"] = simpleMotions["$"],
}

local normalActions = {
	ZQ = function(editor)
		editor:terminate()
	end,
	i = function(editor)
		helpers.pushModeInsert(editor)
	end,
	a = function(editor)
		helpers.performCursorMotion(editor, helpers.textObjects.characterForward)
		helpers.pushModeInsert(editor)
	end,
	[":w<cr>"] = function(editor)  -- TODO command-line mode
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		buf:write()
	end,
}

normalActions[":q<cr>"] = normalActions.ZQ

local insertActions = {
	["<tab>"] = function(editor)
		return true
	end,
	["<space>"] = function(editor)
		helpers.insertTextAtCursor(editor, {" "})
		return false
	end,
	["<cr>"] = function(editor)
		helpers.insertTextAtCursor(editor, {"", ""})
		return false
	end,
	["<bs>"] = function(editor)
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
			toCtx.x = sysencoding.len(line) + 1
		else
			return false
		end
		local to = helpers.finalizeMotion(editor, toCtx)
		helpers.setTextObjectAsRegister(editor, to, helpers.emptyRegisterValue)
		helpers.updateCursorFromMotionContext(editor, toCtx)
		return false
	end,
}

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

local function makeOperatorPendingMotion(toDef)
	return function(editor, toCtx)
		toCtx = helpers.applyMotionToContext(editor, toCtx, toDef)
		return toCtx
	end
end

local function makeInsertMotion(toDef)
	return function(editor)
		local toCtx = helpers.makeMotionContext(editor)
		if toCtx == nil then
			return nil
		end
		toCtx = helpers.applyMotionToContext(editor, toCtx, toDef)
		if toCtx == nil then
			return nil
		end
		helpers.updateCursorFromMotionContext(editor, toCtx)
		return false
	end
end

local function initialize(modeTries)
	local normal = getOrNewTrie(modeTries, "normal")
	local visual = getOrNewTrie(modeTries, "visual")
	local textObject = getOrNewTrie(modeTries, "textObject")  -- a. k. a. operator-pending
	local select_ = getOrNewTrie(modeTries, "select")
	local insert = getOrNewTrie(modeTries, "insert")

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

	for seq, act in pairs(normalActions) do
		putAtKeySeq(normal, seq, act)
	end

	for seq, act in pairs(insertActions) do
		putAtKeySeq(insert, seq, act)
	end
end

return {
	initialize = initialize,
}
