local strptn = require("vim.strptn")
local safeencoding = require("vim.safeencoding")

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
