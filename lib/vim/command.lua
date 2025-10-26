local strptn = require("vim.strptn")
local safeencoding = require("vim.safeencoding")
local option = require("vim.option")

local sourceFile

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
	write = function(editor, argStr)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if #argStr > 0 then
			buf:write(argStr)
		else
			buf:write()
		end
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

commands.w = commands.write
commands.q = commands.quit
commands.nohl = commands.nohlsearch
commands.so = commands.source
commands.hi = commands.highlight
commands.syn = commands.syntax
commands.au = commands.autocmd
commands.setf = commands.setfiletype

local function execute(editor, cmdStr)
	local nonBlankPos = strptn.firstNonSpace(cmdStr)
	if not nonBlankPos then
		return
	end
	cmdStr = safeencoding.sub(cmdStr, nonBlankPos)
	if safeencoding.sub(cmdStr, 1, 1) == "\"" then
		-- Comment
		return
	end
	local argSepPos = strptn.firstSpace(cmdStr)
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
		commandFun(editor, argStr)
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
