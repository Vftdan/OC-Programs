local strptn = require("vim.strptn")
local sysencoding = require("vim.platform.sysencoding")

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
}

commands.w = commands.write
commands.q = commands.quit

local function execute(editor, cmdStr)
	local nonBlankPos = strptn.firstNonSpace(cmdStr)
	if not nonBlankPos then
		return
	end
	cmdStr = sysencoding.sub(cmdStr, nonBlankPos)
	local argSepPos = strptn.firstSpace(cmdStr)
	local cmdName, argStr
	if argSepPos then
		cmdName = sysencoding.sub(cmdStr, 1, argSepPos - 1)
		argStr = sysencoding.sub(cmdStr, argSepPos)
		nonBlankPos = strptn.firstNonSpace(argStr)
		if not nonBlankPos then
			argStr = ""
		else
			argStr = sysencoding.sub(argStr, nonBlankPos)
		end
	else
		cmdName = cmdStr
		argStr = ""
	end
	local commandFun = commands[cmdName]
	if commandFun then
		commandFun(editor, argStr)
	end
end

return {
	commands = commands,
	execute = execute,
}
