local editor = require("vim.editor")
local buffer = require("vim.buffer")
local window = require("vim.window")
local textrender = require("vim.platform.textrender")

local function main(...)
	local args = table.pack(...)
	if args.n ~= 1 then
		io.stderr:write("Usage: vim <filename>\n")
		return
	end
	local oldState = textrender.enterScreen()
	local ed = editor.Editor()
	local buf = buffer.fromFile(args[1])
	ed:registerBuffer(buf)
	local win = window.withBuffer(buf)
	ed:setCurrentWindowId(ed:registerWindow(win))
	ed:run()
	textrender.leaveScreen(oldState)
end

return {
	main = main,
}
