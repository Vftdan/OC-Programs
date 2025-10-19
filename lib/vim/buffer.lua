local makeClass = require("vim.makeclass")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")

local Buffer = makeClass {
	init = function(self)
		self._lines = {}
	end,
	getLineCount = function(self)
		return #self._lines
	end,
	getLine = function(self, i)
		return self._lines[i]
	end,
	read = function(self)
		local f = self._filename and io.open(self._filename, "r")
		local lines = {}
		if f ~= nil then
			local line = f:read()
			while line ~= nil do
				lines[#lines + 1] = line
				line = f:read()
			end
			f:close()
		end
		if #lines < 1 then
			lines[1] = ""
		end
		self._lines = lines
	end,
	write = function(self, filename)
		-- TODO writebackup
		filename = filename or self._filename
		if not filename then
			return
		end
		local f = io.open(filename or self._filename, "w")
		if f == nil then
			return
		end
		f:write(self:getLine(1))
		for i = 2, self:getLineCount() do
			f:write("\n" .. self:getLine(i))
		end
		f:close()
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
		end
		for i, line in itertools.reversedIpairs(txt) do
			if i == #txt then
				line = line .. suffix
			end
			if i == 1 then
				line = prefix .. line
			end
			table.insert(self._lines, begY, line)
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
