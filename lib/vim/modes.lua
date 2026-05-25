local helpers = require("vim.helpers")
local typeahead = require("vim.typeahead")
local safeencoding = require("vim.safeencoding")
local itertools = require("vim.itertools")

local function normalModeSingle(editor)
	editor.typeahead:setModeMappings(editor.mappings.n)
	local cons = editor.modeTries.normal:consumer()
	local i = 0
	local prefix = {}
	local countStr = helpers.pullCountString(editor)
	if countStr == nil then
		return nil
	end
	if #countStr > 0 then
		helpers.setRepeatCount(editor, tonumber(countStr))
	else
		helpers.setRepeatCount(editor, 0)
	end
	while editor:notInterrupted() do
		i = i + 1
		editor:render()
		if i == 1 then
			editor.typeahead:applyModeMappings()
		end
		local key = editor.typeahead:peek(i)
		if key == nil or key == "C-c" then
			-- Clear typeahead
			for _ = 1, i do
				editor.typeahead:pull()
			end
			return false
		end
		prefix[i] = key
		if not cons:next(key) then
			break
		end
		if not cons:hasNext() then
			break
		end
	end
	if cons ~= nil then
		local len, action = cons:getDeepest()
		if len > 0 then
			for _ = 1, len do
				editor.typeahead:pull()
			end
			action(editor)
			return true
		else
			-- Drop one key
			editor.typeahead:pull()
			return false
		end
	else
		return false
	end
end

local function normalMode(editor)
	while editor:notInterrupted() do
		if normalModeSingle(editor) == nil then
			break
		end
		editor:render()
	end
end

local function textObject(editor)
	editor.typeahead:setModeMappings(editor.mappings.o)
	local cons = editor.modeTries.textObject:consumer()
	local toCtx = helpers.makeMotionContext(editor)
	local i = 0
	local prefix = {}
	local countStr = helpers.pullCountString(editor)
	if #countStr > 0 then
		local countMultiplier = helpers.getRepeatCount1(editor)
		helpers.setRepeatCount(editor, tonumber(countStr) * countMultiplier)
	end
	while editor:notInterrupted() do
		i = i + 1
		editor:render()
		if i == 1 then
			editor.typeahead:applyModeMappings()
		end
		local key = editor.typeahead:peek(i)
		if key == nil or key == "C-c" then
			-- Clear typeahead
			for _ = 1, i do
				editor.typeahead:pull()
			end
			cons = nil
			break
		end
		prefix[i] = key
		if not cons:next(key) then
			break
		end
		if not cons:hasNext() then
			break
		end
	end
	if cons ~= nil then
		local len, action = cons:getDeepest()
		if len > 0 then
			for _ = 1, len do
				editor.typeahead:pull()
			end
			toCtx = action(editor, toCtx)
			if toCtx == nil then
				return nil
			end
			local to = helpers.finalizeMotion(editor, toCtx)
			return to
		else
			-- Drop one key
			editor.typeahead:pull()
			return nil
		end
	else
		return nil
	end
end

-- borrow change
local function insertModeSingle(editor, change)
	editor.typeahead:setModeMappings(editor.mappings.i)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	buf:cleanFinalizedChanges()
	local ownChange = false
	if not change or change:getBuffer() ~= buf or change:isFinalized() then
		ownChange = true
		local cursorTo = helpers.makeFinalizedEmptyCursorMotion(editor)
		change = buf:startStagingChange(helpers.getTextObjectEnds(editor, cursorTo))
		table.insert(buf.insertStagingStack, change)
	end
	local cons = editor.modeTries.insert:consumer()
	local i = 0
	local prefix = {}
	helpers.setRepeatCount(editor, 0)
	while editor:notInterrupted() do
		i = i + 1
		editor:render()
		if i == 1 then
			editor.typeahead:applyModeMappings()
			editor.typeahead:applyLangMappings()
		end
		local key = editor.typeahead:peek(i)
		if key == nil or key == "C-c" then
			-- Clear typeahead
			for _ = 1, i do
				editor.typeahead:pull()
			end
			return nil
		end
		prefix[i] = key
		if not cons:next(key) then
			break
		end
		if not cons:hasNext() then
			break
		end
	end
	local len, action = cons:getDeepest()
	if len > 0 then
		for _ = 1, len do
			editor.typeahead:pull()
		end
		local shouldEnd = action(editor, change)
		if ownChange and not change:isFinalized() then
			change:commit()
			table.remove(buf.insertStagingStack)
		end
		editor:render()
		if shouldEnd then
			return nil
		end
		return true
	else
		local ch = helpers.pullInputCharacter(editor)
		if ch ~= nil then
			helpers.insertTextAtCursor(editor, {ch})
			-- local cursorToCtx = helpers.makeMotionContext(editor)
			-- cursorToCtx.exclusive = true
			-- local cursorTo = helpers.finalizeMotion(editor, cursorToCtx)
			-- local fakeRegValue = helpers.registerValueFromText(editor, {ch})
			-- helpers.setTextObjectAsRegister(editor, cursorTo, fakeRegValue)
			-- helpers.performCursorMotion(editor, helpers.textObjects.characterForward)
		end
		if ownChange then
			change:commit()
			table.remove(buf.insertStagingStack)
		end
		return true
	end
end

-- move change
local function insertMode(editor, change)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	win:setVisualSelection(nil)  -- when entering from v_c, should it be fixed somewhere else instead?
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local repeatCount = helpers.getRepeatCount1(editor)
	helpers.setRepeatCount(editor, 0)
	if not change then
		local cursorTo = helpers.makeFinalizedEmptyCursorMotion(editor)
		change = buf:startStagingChange(helpers.getTextObjectEnds(editor, cursorTo))
	end
	table.insert(buf.insertStagingStack, change)
	editor:setModeMessage("-- INSERT --")
	while editor:notInterrupted() do
		if insertModeSingle(editor, change) == nil then
			break
		end
		editor:render()
	end
	if not change:isFinalized() then
		if repeatCount > 1 and editor:notInterrupted() then
			local txt = change:getText()
			for yieldCounter = 2, repeatCount do
				if yieldCounter % 10 == 0 then 
					editor.typeahead:yieldCPU()
					if not editor:notInterrupted() then
						break
					end
				end
				change:splice(txt, 1, 1, 0, 1)
			end
		end
		change:commit()
	end
	table.remove(buf.insertStagingStack)
	buf:cleanFinalizedChanges()
	editor:setModeMessage("")
	editor:render()
end

local function visualMode(editor, toCtx)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	editor.typeahead:setModeMappings(editor.mappings.v)
	local shouldEnd = false
	while editor:notInterrupted() and not shouldEnd do
		if not toCtx then
			toCtx = helpers.makeMotionContext(editor)
			toCtx.linewise = false
		end
		toCtx.exclusive = false
		if toCtx.linewise then
			editor:setModeMessage("-- VISUAL LINE --")
		else
			editor:setModeMessage("-- VISUAL --")
		end
		helpers.motionContextIntoBounds(editor, toCtx)
		helpers.scrollToMotionContextEnd(editor, toCtx)
		helpers.updateCursorFromMotionContext(editor, toCtx)
		win:setVisualSelection(toCtx)

		local cons = editor.modeTries.visual:consumer()
		local i = 0
		local prefix = {}
		local countStr = helpers.pullCountString(editor)
		if countStr == nil then
			return nil
		end
		if #countStr > 0 then
			helpers.setRepeatCount(editor, tonumber(countStr))
		else
			helpers.setRepeatCount(editor, 0)
		end
		while editor:notInterrupted() do
			i = i + 1
			editor:render()
			if i == 1 then
				editor.typeahead:applyModeMappings()
			end
			local key = editor.typeahead:peek(i)
			if key == nil or key == "C-c" then
				-- Clear typeahead
				for _ = 1, i do
					editor.typeahead:pull()
				end
				cons = nil
				break
			end
			prefix[i] = key
			if not cons:next(key) then
				break
			end
			if not cons:hasNext() then
				break
			end
		end
		if cons ~= nil then
			local len, action = cons:getDeepest()
			if len > 0 then
				for _ = 1, len do
					editor.typeahead:pull()
				end
				shouldEnd, toCtx = action(editor, toCtx)
				if toCtx == nil then
					break
				end
			else
				-- Drop one key
				editor.typeahead:pull()
			end
		else
			break
		end
	end
	win:setVisualSelection(nil)
	editor:setModeMessage("")
	editor:render()
end

local cmdline = function(editor, opts)
	opts = opts or {}
	local prompt = opts.prompt or ""
	local promptLength = safeencoding.len(prompt)
	local state = {text = opts.text or "", finished = false, history = itertools.collect(ipairs(opts.history or {}))}
	local lastText = state.text
	state.x = safeencoding.len(state.text) + 1
	table.insert(state.history, state.text)
	state.historyPos = #state.history
	editor:setCmdlineRunning(true)
	editor.typeahead:setModeMappings(editor.mappings.c)
	while editor:isCmdlineRunning() and not state.finished and state.text do
		editor:setCmdlineCursor(promptLength + state.x)
		editor:setCmdlineMessage(prompt .. (state.text or ""))
		local cons = editor.modeTries.cmdline:consumer()
		local i = 0
		local prefix = {}
		helpers.setRepeatCount(editor, 0)
		while editor:notInterrupted() do
			i = i + 1
			editor:render()
			if i == 1 then
				editor.typeahead:applyModeMappings()
				editor.typeahead:applyLangMappings()
			end
			local key = editor.typeahead:peek(i)
			if key == nil or key == "C-c" then
				-- Clear typeahead
				for _ = 1, i do
					editor.typeahead:pull()
				end
				state.text = nil
				state.finished = true
				break
			end
			prefix[i] = key
			if not cons:next(key) then
				break
			end
			if not cons:hasNext() then
				break
			end
		end
		if not state.finished and state.text then
			local len, action = cons:getDeepest()
			if len > 0 then
				for _ = 1, len do
					editor.typeahead:pull()
				end
				action(editor, state)
			else
				local ch = helpers.pullInputCharacter(editor)
				if ch ~= nil then
					state.text = safeencoding.sub(state.text, 1, state.x - 1) .. ch .. safeencoding.sub(state.text, state.x)
					state.x = state.x + safeencoding.len(ch)
				end
			end
			lastText = state.text or lastText
		end
	end
	if opts.history and lastText ~= opts.history[state.historyPos] and #lastText > 0 then
		table.insert(opts.history, lastText)
	end
	editor:setCmdlineRunning(true)
	editor:setCmdlineCursor(nil)
	editor:render()
	editor:setCmdlineRunning(false)
	return state.text
end

return {
	normalModeSingle = normalModeSingle,
	normalMode = normalMode,
	textObject = textObject,
	insertModeSingle = insertModeSingle,
	insertMode = insertMode,
	visualMode = visualMode,
	cmdline = cmdline,
}
