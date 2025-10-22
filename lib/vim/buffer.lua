local makeClass = require("vim.makeclass")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")

local weakMapMeta = {__mode = "k"}
local function weakMap()
	return setmetatable({}, weakMapMeta)
end

local Buffer = makeClass {
	init = function(self)
		self._lines = {}
		self._cacheRoot = {}
	end,
	setEditor = function(self, editor)
		self._editor = editor
	end,
	getLineCount = function(self)
		return #self._lines
	end,
	getLine = function(self, i)
		return self._lines[i]
	end,
	getScopedLineCache = function(self, i, scope)
		if scope == nil then
			return nil
		end
		local lineCache = self._cacheRoot[i]
		if not lineCache then
			return nil
		end
		return lineCache[scope]
	end,
	setScopedLineCache = function(self, i, scope, value)
		if scope == nil then
			return
		end
		local lineCache = self._cacheRoot[i]
		if not lineCache then
			return
		end
		lineCache[scope] = value
	end,
	read = function(self)
		local f = self._filename and io.open(self._filename, "r")
		local lines = {}
		local cacheRoot = {}
		if f ~= nil then
			local line = f:read()
			while line ~= nil do
				lines[#lines + 1] = line
				cacheRoot[#lines] = weakMap()
				line = f:read()
			end
			f:close()
		end
		if #lines < 1 then
			lines[1] = ""
			cacheRoot[1] = weakMap()
		end
		self._lines = lines
		self._cacheRoot = cacheRoot
	end,
	write = function(self, filename)
		-- TODO writebackup
		filename = filename or self._filename
		if not filename then
			if self._editor then
				self._editor:echoErr("No file name")
			end
			return
		end
		local f, reason = io.open(filename, "w")
		if f == nil then
			if self._editor then
				self._editor:echoErr("Failed to open:", reason)
			end
			return
		end
		local success = true
		local numLines = self:getLineCount()
		success, reason = pcall(f.write, f, self:getLine(1))
		for i = 2, numLines do
			if success then
				success, reason = pcall(f.write, f, "\n" .. self:getLine(i))
			else
				break
			end
		end
		if not success then
			if self._editor then
				self._editor:echoErr("Error while writing:", reason)
			end
			return
		end
		success, reason = pcall(f.close, f)
		if not success then
			if self._editor then
				self._editor:echoErr("Error while closing:", reason)
			end
			return
		end
		if self._editor then
			self._editor:echo(string.format("%q %dL written", filename, numLines))
		end
	end,
	--- Copies characterwise lines or their parts into an array
	-- Both beginning and ending characters are included
	-- If the ending is before the beginning, {""} is returned
	-- Out-of-bounds (non-positive and greater than length) positions are allowed and can be used to get empty strings
	-- @returns a non-empty array of strings
	getTextBetween = function(self, begX, begY, edX, edY)
		local result = {}
		if edY < begY or edY == begY and edX < begX then
			table.insert(result, "")
			return result
		end
		for i = begY, edY do
			if i < 1 or i > #self._lines then
				table.insert(result, "")
			else
				local line = self._lines[i] or ""
				if i == edY then
					if edX < 1 then
						line = ""
					else
						line = sysencoding.sub(line, 1, edX)
					end
				end
				if i == begY then
					if begX >= 1 then
						line = sysencoding.sub(line, begX)
					end
				end
				table.insert(result, line)
			end
		end
		return result
	end,
	--- Deletes and pastes characterwise lines or their parts from an array
	-- Both beginning and ending characters are deleted
	-- If the ending is exactly one character before and in the same line as the beginning,
	-- nothing will be deleted
	-- If the ending is further before the beginning, nothing will be done
	-- @param txt a non-empty array of strings
	setTextBetween = function(self, txt, begX, begY, edX, edY)
		if edY < begY or edY == begY and edX + 1 < begX then
			print(begX, begY, edX, edY)
			error()
			return
		end
		local begLine = self._lines[begY] or ""
		local edLine = self._lines[edY] or ""
		local prefix, suffix
		if begX > 1 then
			prefix = sysencoding.sub(begLine, 1, begX - 1)
		else
			prefix = ""
		end
		if edX > 0 then
			suffix = sysencoding.sub(edLine, edX + 1)
		else
			suffix = edLine
		end
		for i = edY, begY, -1 do
			table.remove(self._lines, i)
			table.remove(self._cacheRoot, i)
		end
		for i, line in itertools.reversedIpairs(txt) do
			if i == #txt then
				line = line .. suffix
			end
			if i == 1 then
				line = prefix .. line
			end
			table.insert(self._lines, begY, line)
			table.insert(self._cacheRoot, begY, weakMap())
		end
	end,
	setFilename = function(self, name)
		self._filename = name
	end,
	getFilename = function(self)
		return self._filename
	end,
}

local function fromFile(name)
	local buf = Buffer()
	buf:setFilename(name)
	buf:read()
	return buf
end

return {
	Buffer = Buffer,
	fromFile = fromFile,
}
