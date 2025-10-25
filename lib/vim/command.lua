local strptn = require("vim.strptn")
local safeencoding = require("vim.safeencoding")
local option = require("vim.option")

local function optionCommand(editor, argStr, opts)
	opts = opts or {}
	local args = {}
	while #argStr > 0 do
		local argSepPos = strptn.firstUnescapedSpace(argStr)
		if not argSepPos then
			table.insert(args, argStr)
			break
		end
		nextArg = safeencoding.sub(argStr, 1, argSepPos - 1)
		table.insert(args, nextArg)
		argStr = safeencoding.sub(argStr, argSepPos)
		nonBlankPos = strptn.firstNonSpace(argStr)
		if not nonBlankPos then
			break
		end
		argStr = safeencoding.sub(argStr, nonBlankPos)
	end
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
	end,
	set = function(editor, argStr)
		optionCommand(editor, argStr)
	end,
}

commands.w = commands.write
commands.q = commands.quit
commands.nohl = commands.nohlsearch

local function execute(editor, cmdStr)
	local nonBlankPos = strptn.firstNonSpace(cmdStr)
	if not nonBlankPos then
		return
	end
	cmdStr = safeencoding.sub(cmdStr, nonBlankPos)
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

return {
	commands = commands,
	execute = execute,
}
