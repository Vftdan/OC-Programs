local editor = require("vim.editor")
local buffer = require("vim.buffer")
local window = require("vim.window")
local textrender = require("vim.platform.textrender")
local helpers = require("vim.helpers")
local command = require("vim.command")

local function runInitCommands(editor, preRcCommands, postRcCommands, rcFile, gotoLine)
	for _, cmd in ipairs(preRcCommands) do
		command.execute(editor, cmd)
		if not editor:isRunning() then
			return
		end
	end
	if rcFile ~= "NORC" and rcFile ~= "NONE" then
		local rcFh = io.open(rcFile, "r")
		if rcFh then
			while true do
				local cmd = rcFh:read()
				if cmd == nil then
					break
				end
				command.execute(editor, cmd)
				if not editor:isRunning() then
					return
				end
			end
		end
	end
	for _, cmd in ipairs(postRcCommands) do
		command.execute(editor, cmd)
		if not editor:isRunning() then
			return
		end
	end
	local buf = editor:getCurrentBuffer()
	local numLines = buf:getLineCount()
	if gotoLine < 0 or gotoLine > numLines then
		gotoLine = numLines
	end
	if gotoLine < 1 then
		gotoLine = 1
	end
	local cursorToCtx = helpers.makeMotionContext(editor)
	cursorToCtx.y = gotoLine
	helpers.motionContextIntoBounds(editor, cursorToCtx)
	helpers.scrollToMotionContextEnd(editor, cursorToCtx)
	helpers.updateCursorFromMotionContext(editor, cursorToCtx)
end

local function main(...)
	local args = table.pack(...)

	-- Parse arguments
	local filesToEdit = {}
	local rcFile = "/home/.vimrc"
	local preRcCommands = {}
	local postRcCommands = {}
	local argumentsEnded = false
	local gotoLine = 1
	local i = 0
	local usageString = "Usage: vim [-c COMMAND] [--cmd COMMAND] [+COMMAND] [-u VIMRC] [--] FILENAME"
	while i < args.n do
		i = i + 1
		local opt = args[i]
		local nextOpt = args[i + 1]
		if not argumentsEnded and opt:sub(1, 1) == "-" then
			if opt == "-c" then
				if not nextOpt then
					io.stderr:write("Argument missing after: \"-c\"\n")
					return
				end
				i = i + 1
				table.insert(postRcCommands, nextOpt)
			elseif opt == "--cmd" then
				if not nextOpt then
					io.stderr:write("Argument missing after: \"--cmd\"\n")
					return
				end
				i = i + 1
				table.insert(preRcCommands, nextOpt)
			elseif opt == "-u" then
				if not nextOpt then
					io.stderr:write("Argument missing after: \"-u\"\n")
					return
				end
				i = i + 1
				rcFile = nextOpt
			elseif opt == "--" then
				argumentsEnded = true
			elseif opt == "--version" then
				print("vim implementation by vftdan, indev")
			elseif opt == "-h" or opt == "--help" then
				print(usageString)
				return
			else
				io.stderr:write(("Unknown option argument: %q\nMore info with: \"vim -h\"\n"):format(opt))
				return
			end
		elseif not argumentsEnded and opt:sub(1, 1) == "+" then
			local cmd = opt:sub(2)
			if #cmd == 0 then
				gotoLine = -1
			elseif cmd:find("^%d+$") then
				gotoLine = tonumber(cmd)
			else
				table.insert(postRcCommands, cmd)
			end
		else
			table.insert(filesToEdit, opt)
		end
	end
	if #filesToEdit ~= 1 then
		io.stderr:write("Exactly one file to edit expected\n")
		return
	end

	-- Initialize
	local oldState = textrender.enterScreen()
	local ed = editor.Editor()
	local buf = buffer.fromFile(filesToEdit[1])
	ed:registerBuffer(buf)
	local win = window.withBuffer(buf)
	ed:setCurrentWindowId(ed:registerWindow(win))

	runInitCommands(ed, preRcCommands, postRcCommands, rcFile, gotoLine)
	ed:run()
	textrender.leaveScreen(oldState)
end

return {
	main = main,
}
