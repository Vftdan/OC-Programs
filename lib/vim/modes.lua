local helpers = require("vim.helpers")
local typeahead = require("vim.typeahead")

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
	while editor:isRunning() do
		i = i + 1
		editor:render()
		if i == 1 then
			editor.typeahead:applyModeMappings()
		end
		local key = editor.typeahead:peek(i)
		if key == nil then
			return nil
		end
		if key == "C-c" then
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
	while editor:isRunning() do
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
	while editor:isRunning() do
		i = i + 1
		editor:render()
		if i == 1 then
			editor.typeahead:applyModeMappings()
		end
		local key = editor.typeahead:peek(i)
		if key == nil then
			return nil
		end
		if key == "C-c" then
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

local function insertModeSingle(editor)
	editor.typeahead:setModeMappings(editor.mappings.i)
	local cons = editor.modeTries.insert:consumer()
	local i = 0
	local prefix = {}
	helpers.setRepeatCount(editor, 0)
	while editor:isRunning() do
		i = i + 1
		editor:render()
		if i == 1 then
			editor.typeahead:applyModeMappings()
			editor.typeahead:applyLangMappings()
		end
		local key = editor.typeahead:peek(i)
		if key == nil then
			return nil
		end
		if key == "C-c" then
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
		local shouldEnd = action(editor)
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
		return true
	end
end

local function insertMode(editor)
	editor:setModeMessage("-- INSERT --")
	while editor:isRunning() do
		if insertModeSingle(editor) == nil then
			break
		end
		editor:render()
	end
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
	while editor:isRunning() and not shouldEnd do
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
		while editor:isRunning() do
			i = i + 1
			editor:render()
			if i == 1 then
				editor.typeahead:applyModeMappings()
			end
			local key = editor.typeahead:peek(i)
			if key == nil then
				return nil
			end
			if key == "C-c" then
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

return {
	normalModeSingle = normalModeSingle,
	normalMode = normalMode,
	textObject = textObject,
	insertModeSingle = insertModeSingle,
	insertMode = insertMode,
	visualMode = visualMode,
}
