local strptn = require("vim.strptn")
local safeencoding = require("vim.safeencoding")
local option = require("vim.option")
local helpers = require("vim.helpers")
local Trie = require("vim.trie")
local typeahead = require("vim.typeahead")
local keyseq = require("vim.keyseq")

local sourceFile, execute, resolveRange

local function runtimeFile(editor, name, all)
	local success = false
	for _, dir in ipairs(editor.runtimeDirs) do
		local found = sourceFile(editor, dir .. "/" .. name)
		if found then
			success = true
			if not all then
				break
			end
		end
	end
	return success
end

local function splitArgs(argStr)
	local args = {}
	while #argStr > 0 do
		local argSepPos = strptn.firstUnescapedSpace(argStr)
		if not argSepPos then
			table.insert(args, argStr)
			break
		end
		nextArg = strptn.unescapeBackslash(safeencoding.sub(argStr, 1, argSepPos - 1))
		table.insert(args, nextArg)
		argStr = safeencoding.sub(argStr, argSepPos)
		nonBlankPos = strptn.firstNonSpace(argStr)
		if not nonBlankPos then
			break
		end
		argStr = safeencoding.sub(argStr, nonBlankPos)
	end
	return args
end

local function optionCommand(editor, argStr, opts)
	opts = opts or {}
	local args = splitArgs(argStr)
	for _, arg in ipairs(args) do
		local optName, value = arg, nil
		local method
		local nameEndByte = arg:find("[!=%?%+%-]")

		if safeencoding.sub(arg, 1, 2) == "no" and not nameEndByte then
			-- Are there any option names that actually start with "no"?
			optName = safeencoding.sub(arg, 3)
			method = "disable"
		elseif not nameEndByte then
			method = "enable"
		else
			optName = arg:sub(1, nameEndByte - 1)
			local methodCh = arg:sub(nameEndByte, nameEndByte)
			if methodCh == "!" then
				method = "toggle"
				if nameEndByte < #arg then
					method = "trail"
				end
			elseif methodCh == "?" then
				method = "query"
				if nameEndByte < #arg then
					method = "trail"
				end
			else
				if methodCh == "=" then
					method = "set"
					value = arg:sub(nameEndByte + 1)
				else
					value = arg:sub(nameEndByte + 2)
					if arg:sub(nameEndByte + 1, nameEndByte + 1) ~= "=" then
						method = "trail"
					elseif methodCh == "+" then
						method = "add"
					else
						method = "sub"
					end
				end
			end
		end

		if method == "trail" then
			editor:echoErr("Trailing characters:", arg)
		else
			local opt = option.options[optName]
			if not opt then
				editor:echoErr("Unknown option:", optName)
			elseif not opt[method] then
				editor:echoErr("Invalid option access:", method, optName)
			else
				opt[method](opt, editor, {scope = opts.scope, value = value})
			end
		end
	end
end

local commands = {
	write = function(editor, argStr, rangeTable)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		local opts = {}
		if #argStr > 0 then
			opts.filename = argStr
		end
		if #rangeTable.elements > 0 then
			resolveRange(editor, rangeTable)
			if rangeTable.failure then
				editor:echoErr(rangeTable.failure)
				return
			else
				opts.firstLine = rangeTable.lines[1]
				opts.lastLine = rangeTable.lines[2]
			end
		end
		buf:write(opts)
	end,
	quit = function(editor, argStr)
		editor:terminate()
	end,
	nohlsearch = function(editor, argStr)
		editor.hlsearch = false
		editor:invalidateDisplay()
	end,
	set = function(editor, argStr)
		optionCommand(editor, argStr)
	end,
	source = function(editor, argStr)
		if not sourceFile(editor, argStr) then
			editor:echoErr("Could not find file:", argStr)
		end
	end,
	runtime = function(editor, argStr)
		if not runtimeFile(editor, argStr) then
			editor:echoErr("Could not find file in the runtime directories:", argStr)
		end
	end,
	["runtime!"] = function(editor, argStr)
		if not runtimeFile(editor, argStr, true) then
			editor:echoErr("Could not find file in the runtime directories:", argStr)
		end
	end,
	highlight = function(editor, argStr)
		local args = splitArgs(argStr)
		local i = 1
		local useDefault = false
		local doLink = false
		if args[i] == "default" or args[i] == "def" then
			useDefault = true
			i = i + 1
		end
		if args[i] == "link" then
			doLink = true
			i = i + 1
		end
		local groupName = args[i]
		i = i + 1
		if not groupName then
			editor:echoErr("Not enough arguments: highlight", argStr)
			return
		end
		if doLink then
			local targetName = args[i]
			i = i + 1
			if not targetName then
				editor:echoErr("Not enough arguments: highlight", argStr)
				return
			end
			if i <= #args then
				editor:echoErr("Too many arguments: highlight", argStr)
				return
			end
			if useDefault then
				editor.styleRegistry:linkDefault(groupName, targetName)
			else
				editor.styleRegistry:link(groupName, targetName)
			end
			editor:invalidateDisplay()
		else
			local tbl = {}
			while args[i] do
				local arg = args[i]
				i = i + 1
				local equalsByteIndex = arg:find("=") or #arg + 1
				local key = arg:sub(1, equalsByteIndex - 1)
				local value = arg:sub(equalsByteIndex + 1)
				if key == "ctermbg" or key == "ctermfg" or key == "ctermsp" then
					local color = tonumber(value)
					if not color or color < 0 or color > 15 or color % 1 ~= 0 then
						editor:echoErr("Invalid cterm color:", value)
					else
						tbl[key] = color
					end
				elseif key == "guibg" or key == "guifg" or key == "guisp" then
					local color = tonumber("0x" .. value:sub(2))
					if value:sub(1, 1) ~= "#" or not color or color < 0 or color > 0xFFFFFF or color % 1 ~= 0 then
						editor:echoErr("Invalid hex color:", value)
					else
						tbl[key] = color
					end
				elseif key == "cterm" or key == "gui" then
					for item in value:gmatch("[^,]+") do
						if item == "bold" or item == "italic" or item == "underline" or item == "reverse" then
							tbl[item] = true
						else
							editor:echoErr("Illegal value:", item)
						end
					end
				else
					editor:echoErr("Illegal argument:", arg)
				end
			end
			if useDefault then
				editor.styleRegistry:defineDefault(groupName, tbl)
			else
				editor.styleRegistry:define(groupName, tbl)
			end
			editor:invalidateDisplay()
		end
	end,
	syntax = function(editor, argStr)
		local args = splitArgs(argStr)
		local i = 1
		local subCommand = args[i]
		i = i + 1
		if not subCommand then
			editor:echoErr("Not enough arguments: syntax", argStr)
			return
		end
		if subCommand == "on" then
			if i <= #args then
				editor:echoErr("Too many arguments: syntax", argStr)
				return
			end
			-- TODO invalidate some syntax caches
			editor.enableSyntax = true
			editor:invalidateDisplay()
		elseif subCommand == "off" then
			if i <= #args then
				editor:echoErr("Too many arguments: syntax", argStr)
				return
			end
			editor.enableSyntax = false
			editor:invalidateDisplay()
		elseif subCommand == "match" then
			local buf = editor:getCurrentBuffer()
			if buf == nil then
				return
			end
			local groupName = args[i]
			i = i + 1
			if not groupName then
				editor:echoErr("Not enough arguments: highlight", argStr)
				return
			end
			local pattern
			local options = {}
			while args[i] do
				local arg = args[i]
				i = i + 1
				if arg:find("^%W") then
					local argLen = safeencoding.len(arg)
					local begChar = safeencoding.sub(arg, 1, 1)
					local edChar = safeencoding.sub(arg, argLen, argLen)
					if begChar ~= edChar then
						editor:echoErr("Pattern delimiter not found:", arg)
						return
					end
					local searchString = safeencoding.sub(arg, 2, argLen - 1)
					if searchString:sub(1, 2) == "\\V" or searchString:sub(1, 2) == "\\M" then
						-- nomagic
						searchString = strptn.escapePtn(searchString:sub(3))
					end
					searchString = strptn.unescapeBackslash(searchString)
					local success, reason = strptn.validatePtn(searchString)
					if not success then
						editor:echoErr(("Invalid search string (%s): %s"):format(reason, searchString))
						return
					end
					pattern = searchString
				elseif arg == "keepend" or arg == "excludenl" then
					options[arg] = true
				else
					editor:echoErr("Invalid argument:", arg)
				end
			end
			if not pattern then
				editor:echoErr("Missing pattern: syntax", argStr)
				return
			end
			buf.syntaxRegistry:defineMatch(groupName, pattern, options)
			editor:invalidateDisplay()
		elseif subCommand == "keyword" then
			local buf = editor:getCurrentBuffer()
			if buf == nil then
				return
			end
			local groupName = args[i]
			i = i + 1
			if not groupName then
				editor:echoErr("Not enough arguments: highlight", argStr)
				return
			end
			local pattern
			local options = {}
			local optionsEnded = false
			local kws = {}
			while args[i] do
				local arg = args[i]
				i = i + 1
				if not optionsEnded and false then  -- TODO
					options[arg] = true
				elseif not optionsEnded and arg == "--" then
					optionsEnded = true
				else
					table.insert(kws, arg)
				end
			end
			buf.syntaxRegistry:defineKeyword(groupName, kws, options)
			editor:invalidateDisplay()
		elseif subCommand == "clear" then
			if i <= #args then
				editor:echoErr("Too many arguments: syntax", argStr)
				return
			end
			local buf = editor:getCurrentBuffer()
			if buf == nil then
				return
			end
			buf.syntaxRegistry:clear()
			editor:invalidateDisplay()
		else
			editor:echoErr("Invalid :syntax subcommand", subCommand)
		end
	end,
	autocmd = function(editor, argStr)
		local origArgStr = argStr
		local argSepPos = strptn.firstUnescapedSpace(argStr)
		if not argSepPos then
			editor:echoErr("Not enough arguments: autocmd", origArgStr)
			return
		end
		local events = strptn.splitBy(safeencoding.sub(argStr, 1, argSepPos - 1), ",")
		argStr = safeencoding.sub(argStr, argSepPos)
		nonBlankPos = strptn.firstNonSpace(argStr)
		if not nonBlankPos then
			editor:echoErr("Not enough arguments: autocmd", origArgStr)
			return
		end
		argStr = safeencoding.sub(argStr, nonBlankPos)
		argSepPos = strptn.firstUnescapedSpace(argStr) or #argStr + 1
		local glob = safeencoding.sub(argStr, 1, argSepPos - 1)
		local cbCmd = safeencoding.sub(argStr, argSepPos + 1)
		editor.autocmdRegistry:register(events, glob, cbCmd)
	end,
	setfiletype = function(editor, argStr)
		option.options.syntax:set(editor, {value = argStr, scope = "local"})
	end,
}

local function registerMappingCommand(name, tables, isRecursive)
	commands[name] = function(editor, argStr, rangeTable)
		if #rangeTable.elements > 0 then
			editor:echoErr("No range allowed")
			return
		end
		local origArgStr = argStr
		local argSepPos = strptn.firstUnescapedSpace(argStr)
		if not argSepPos then
			editor:echoErr("Not enough arguments: " .. name, origArgStr)
			return
		end
		local lhs = keyseq.parseKeySequence(safeencoding.sub(argStr, 1, argSepPos - 1), typeahead.keyNormalisation, typeahead.modifierOrder)
		argStr = safeencoding.sub(argStr, argSepPos)
		local nonBlankPos = strptn.firstNonSpace(argStr)
		if not argSepPos then
			editor:echoErr("Not enough arguments: " .. name, origArgStr)
			return
		end
		argStr = safeencoding.sub(argStr, nonBlankPos)
		local rhs = keyseq.parseKeySequence(argStr, typeahead.keyNormalisation, typeahead.modifierOrder)
		for _, key in ipairs(tables) do
			local trie = editor.mappings[key]
			if not trie then
				trie = Trie()
				editor.mappings[key] = trie
			end
			trie:put(lhs, {dst = rhs, remap = isRecursive})
		end
	end
end

local mappingModes = {
	[""] = {"n", "v", "o"},
	["!"] = {"i", "c"},
	n = {"n"},
	x = {"v"},
	v = {"v"},
	i = {"i"},
	c = {"c"},
	o = {"o"},
}

for prefix, tables in pairs(mappingModes) do
	local suffix = ""
	if prefix == "!" then
		suffix = prefix
		prefix = ""
	end
	registerMappingCommand(prefix .. "noremap" .. suffix, tables, false)
	registerMappingCommand(prefix .. "map" .. suffix, tables, true)
end

commands.w = commands.write
commands.q = commands.quit
commands.nohl = commands.nohlsearch
commands.so = commands.source
commands.hi = commands.highlight
commands.syn = commands.syntax
commands.au = commands.autocmd
commands.setf = commands.setfiletype

local function emptyCommand(editor, rangeTable)
	resolveRange(editor, rangeTable)
	if rangeTable.failure then
		editor:echoErr(rangeTable.failure)
	elseif #rangeTable.elements > 0 then
		local toCtx = helpers.makeMotionContext(editor)
		toCtx.y = rangeTable.lines[2]
		helpers.motionContextIntoBounds(editor, toCtx)
		helpers.scrollToMotionContextEnd(editor, toCtx)
		helpers.updateCursorFromMotionContext(editor, toCtx)
	end
end

local RANGE_ESCEND_PTN = "[^%d%.%$%%,]"
local function extractRange(editor, rangeCmd)
	-- TODO plus/minus suffixes
	local nonBlankPos = strptn.firstNonSpace(rangeCmd)
	if not nonBlankPos then
		rangeCmd = ""
	else
		rangeCmd = safeencoding.sub(rangeCmd, nonBlankPos)
	end
	local failure = nil
	local wasSemicolon = true
	local expectComma = false
	local elements = {}
	local startByte = 1
	local cmdLen = #rangeCmd
	while startByte <= cmdLen do
		-- Initialize addEmpty as false to distinguish unprocessed "" from "," without checking endsWithComma
		local addEmpty = false
		local nextStartByte = rangeCmd:find(RANGE_ESCEND_PTN, startByte) or cmdLen + 1
		local unprocessed = rangeCmd:sub(startByte, nextStartByte - 1)
		local unprocessedArr = strptn.splitBy(unprocessed, "[,;]", {pattern = true})
		local endsWithComma = false
		local unprocessedLen = #unprocessedArr
		local expectCommaAfter = expectComma
		local addEmptyNext = false
		if unprocessedLen > 1 and #unprocessedArr[unprocessedLen] == 0 then
			endsWithComma = true
			table.remove(unprocessedArr)
		end
		local commaOffset = 0
		for _, elem in ipairs(unprocessedArr) do
			if commaOffset > 0 then
				local commaChar = unprocessed:sub(commaOffset, commaOffset)
				if commaChar == ";" then
					wasSemicolon = true
				end
			end
			commaOffset = commaOffset + 1 + #elem
			expectCommaAfter = false
			if addEmptyNext then
				table.insert(elements, {kind = "empty", absolute = false, fromPrevious = wasSemicolon})
				addEmptyNext = false
			end
			if expectComma then
				if #elem > 0 then
					failure = ("Expected ',' before %q"):format(elem)
				else
					expectComma = false
					expectCommaAfter = true
					addEmpty = true
				end
			else
				if #elem == 0 then
					addEmptyNext = true
					addEmpty = true
				else
					expectCommaAfter = true
					if elem:find("^%d+$") then
						local num = tonumber(elem)
						if num > 999999 then
							num = 999999
						end
						table.insert(elements, {kind = "number", absolute = false, num = num, fromPrevious = wasSemicolon})
					elseif elem == "." then
						table.insert(elements, {kind = "currentLine", absolute = true, fromPrevious = wasSemicolon})
					elseif elem == "$" then
						table.insert(elements, {kind = "lastLine", absolute = true, fromPrevious = wasSemicolon})
					elseif elem == "%" then
						table.insert(elements, {kind = "wholeStart", absolute = true, fromPrevious = wasSemicolon})
						table.insert(elements, {kind = "wholeEnd", absolute = true, fromPrevious = wasSemicolon})
					else
						table.insert(elements, {kind = "error", token = elem, fromPrevious = wasSemicolon})
						failure = ("Invalid range element: %q"):format(elem)
					end
				end
			end
		end
		if endsWithComma then
			local commaChar = unprocessed:sub(commaOffset, commaOffset)
			if commaChar == ";" then
				wasSemicolon = true
			end
		end
		if addEmptyNext and endsWithComma then
			table.insert(elements, {kind = "empty", absolute = false, fromPrevious = wasSemicolon})
		end
		expectComma = expectCommaAfter and not endsWithComma
		addEmpty = endsWithComma
		startByte = nextStartByte
		local missingComma = expectComma
		local byteVal = rangeCmd:sub(nextStartByte, nextStartByte)
		if byteVal == "'" then
			-- Defer failure to range resolution
			nextStartByte = nextStartByte + 1
			-- Marks can only be single-byte
			local markName = rangeCmd:sub(nextStartByte, nextStartByte)
			nextStartByte = nextStartByte + 1
			table.insert(elements, {kind = "mark", mark = markName, absolute = true, fromPrevious = wasSemicolon})
			expectComma = true
		elseif byteVal == "/" or byteVal == "?" then
			failure = "Not implemented: search range"
			break
		elseif byteVal == "\\" then
			failure = "Not implemented: reused search range"
			table.insert(elements, {kind = "search", absolute = true, fromPrevious = wasSemicolon})
			nextStartByte = nextStartByte + 2
			expectComma = true
		else
			if addEmpty then
				table.insert(elements, {kind = "empty", absolute = false, fromPrevious = wasSemicolon})
			end
			missingComma = false
			break
		end
		if missingComma then
			failure = ("Expected ',' before %q"):format(rangeCmd:sub(startByte, nextStartByte - 1))
		end
		startByte = nextStartByte
	end
	return {
		elements = elements,
		failure = failure,
	}, rangeCmd:sub(startByte)
end

function resolveRange(editor, rangeTable)
	local buf = editor:getCurrentBuffer()
	local cursorToCtx = helpers.makeMotionContext(editor)
	local visualToCtx = helpers.restoreSelectionMotionContext(editor)
	if visualToCtx.y < visualToCtx.initialY or visualToCtx.y == visualToCtx.initialY and visualToCtx.x < visualToCtx.initialX then
		visualToCtx.x, visualToCtx.initialX = visualToCtx.initialX, visualToCtx.x
		visualToCtx.y, visualToCtx.initialY = visualToCtx.initialY, visualToCtx.y
	end
	local lastLine = buf:getLineCount()
	local lineNr = cursorToCtx.y
	local prevLineNr = lineNr
	for _, entry in ipairs(rangeTable.elements) do
		prevLineNr = lineNr
		local kind = entry.kind
		if kind == "empty" then
			-- Do nothing
		elseif kind == "number" then
			lineNr = entry.num
		elseif kind == "currentLine" then
			lineNr = cursorToCtx.y
		elseif kind == "lastLine" or kind == "wholeEnd" then
			lineNr = lastLine
		elseif kind == "wholeStart" then
			lineNr = 1
		elseif kind == "mark" then
			local markName = entry.mark
			if markName == "." then
				lineNr = cursorToCtx.y
			elseif markName == "<" then
				lineNr = visualToCtx.initialY
			elseif markName == ">" then
				lineNr = visualToCtx.y
			else
				rangeTable.failure = ("Unknown mark: %q"):format(markName)
			end
		end
		entry.lineNr = lineNr
	end
	rangeTable.lines = {prevLineNr, lineNr}
end

function execute(editor, cmdStr)
	local rangeTable, cmdStr = extractRange(editor, cmdStr)
	if rangeTable.failure then
		editor:echoErr("Range parsing error:", rangeTable.failure)
		return
	end
	local nonBlankPos = strptn.firstNonSpace(cmdStr)
	if not nonBlankPos then
		emptyCommand(editor, rangeTable)
		return
	end
	cmdStr = safeencoding.sub(cmdStr, nonBlankPos)
	if safeencoding.sub(cmdStr, 1, 1) == "\"" then
		-- Comment
		emptyCommand(editor, rangeTable)
		return
	end
	local argSepPos = strptn.firstNonAlBang(cmdStr)
	local cmdName, argStr
	if argSepPos then
		cmdName = safeencoding.sub(cmdStr, 1, argSepPos - 1)
		argStr = safeencoding.sub(cmdStr, argSepPos)
		nonBlankPos = strptn.firstNonSpace(argStr)
		if not nonBlankPos then
			argStr = ""
		else
			argStr = safeencoding.sub(argStr, nonBlankPos)
		end
	else
		cmdName = cmdStr
		argStr = ""
	end
	local commandFun = commands[cmdName]
	if commandFun then
		commandFun(editor, argStr, rangeTable)
	else
		editor:echoErr("Not an editor command:", cmdName)
	end
end

local function sourceFileHandle(editor, fh)
	while true do
		local cmd = fh:read()
		if cmd == nil or cmd:find("^%s*finish$") then
			return
		end
		execute(editor, cmd)
		if not editor:isRunning() then
			return
		end
	end
end

function sourceFile(editor, fname)
	local fh = io.open(fname, "r")
	if fh then
		sourceFileHandle(editor, fh)
	else
		return false
	end
	return true
end

return {
	commands = commands,
	execute = execute,
	sourceFileHandle = sourceFileHandle,
	sourceFile = sourceFile,
	runtimeFile = runtimeFile,
}
