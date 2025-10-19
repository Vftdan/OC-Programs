local textrender = require("vim.platform.textrender")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")
local makeClass = require("vim.makeclass")

local Window = makeClass {
	init = function(self, buffer)
		self.currentBuffer = buffer
		self._scrollX = 0
		self._scrollY = 0
	end,
	setEditor = function(self, editor)
		self._editor = editor
	end,
	render = function(self)
		local normalStyle = textrender.interpretStyle(self._editor.styleRegistry:resolveStack({"normal"}))
		local cursorStyle = textrender.interpretStyle(self._editor.styleRegistry:resolveStack({"normal", "cursor"}))
		local eobStyle = textrender.interpretStyle(self._editor.styleRegistry:resolveStack({"normal", "endofbuffer"}))
		local lineNrStyle = textrender.interpretStyle(self._editor.styleRegistry:resolveStack({"normal", "linenr"}))
		local statusLineStyle = textrender.interpretStyle(self._editor.styleRegistry:resolveStack({"normal", "statusline"}))
		local eobChunk = {"~"}
		itertools.update(eobChunk, eobStyle)
		local width, height = textrender.getTermSize()
		height = height - 1  -- MsgArea is not managed by the window
		eobChunk[1] = eobChunk[1] .. itertools.repeatString(" ", width - 1)
		local n = self.currentBuffer:getLineCount()
		local maxNrDigits = sysencoding.len(tostring(n))
		local contentWidth = width - maxNrDigits - 1
		local contentHeight = height - 1  -- Reserve status line space
		local cursorX = self._editor._cursorX or 1
		local cursorY = self._editor._cursorY or 1
		local cursorViewportX = cursorX - self._scrollX
		local cursorViewportY = cursorX - self._scrollY
		for i = 1, height do
			textrender.setCursorPos(1, i)
			local lineNr = i + self._scrollY
			if lineNr <= n then
				local nrString = tostring(lineNr)
				while sysencoding.len(nrString) < maxNrDigits do
					nrString = " " .. nrString
				end
				local nrChunk = {nrString .. " "}
				itertools.update(nrChunk, lineNrStyle)
				local viewportLine = sysencoding.sub(self.currentBuffer:getLine(lineNr), 1 + self._scrollX, contentWidth + self._scrollX)
				if cursorY == i and cursorX > 0 then
					local linePre = sysencoding.sub(viewportLine, 1, cursorX - 1)
					local lineCur = sysencoding.sub(viewportLine, cursorX, cursorX)
					if lineCur == "" then
						lineCur = " "
					end
					local linePost = sysencoding.sub(viewportLine, cursorX + 1)
					local remainingLength = contentWidth - sysencoding.len(linePre) - sysencoding.len(linePost) - 1
					local rightPad = ""
					if remainingLength > 0 then
						rightPad = itertools.repeatString(" ", remainingLength)
					end
					local chunkPre = {linePre}
					local chunkCur = {lineCur}
					local chunkPost = {linePost .. rightPad}
					itertools.update(chunkPre, normalStyle)
					itertools.update(chunkCur, cursorStyle)
					itertools.update(chunkPost, normalStyle)
					textrender.blitAll{
						nrChunk,
						chunkPre,
						chunkCur,
						chunkPost,
					}
				else
					local remainingLength = contentWidth - sysencoding.len(viewportLine)
					local rightPad = ""
					if remainingLength > 0 then
						rightPad = itertools.repeatString(" ", remainingLength)
					end
					local textChunk = {viewportLine .. rightPad}
					itertools.update(textChunk, normalStyle)
					textrender.blitAll{
						nrChunk,
						textChunk,
					}
				end
			else
				textrender.blitAll{
					eobChunk,
				}
			end
		end

		-- Status line
		textrender.setCursorPos(1, height)
		local filename = self.currentBuffer:getFilename()
		filename = sysencoding.sub(filename, 1, width)
		local remainingLength = width - sysencoding.len(filename)
		local rightPad = ""
		if remainingLength > 0 then
			rightPad = itertools.repeatString(" ", remainingLength)
		end
		local filenameChunk = {filename .. rightPad}
		itertools.update(filenameChunk, statusLineStyle)
		textrender.blitAll{
			filenameChunk,
		}
	end,
}

local function withBuffer(buf)
	return Window(buf)
end

return {
	withBuffer = withBuffer,
}
