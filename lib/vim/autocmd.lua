local makeClass = require("vim.makeclass")
local strptn = require("vim.strptn")
local command = require("vim.command")

local AutocmdRegistry = makeClass {
	init = function(self, editor)
		self._editor = editor
		self._byEvent = {bufnewfile = {}, bufread = {}}
	end,
	clear = function(self)
		for k in pairs(self._byEvent) do
			self._byEvent[k] = {}
		end
	end,
	register = function(self, events, glob, cmd)
		local ptn = strptn.fromGlob(glob)
		for _, ev in ipairs(events) do
			local tbl = self._byEvent[ev:lower()]
			if not tbl then
				self._editor:echoErr("No such event:", ev)
			else
				table.insert(tbl, {pattern = ptn, command = cmd})
			end
		end
	end,
	fireCurrentBuffer = function(self, ev)
		local buf = self._editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		self:fire(ev, buf:getFilename() or "")
	end,
	fire = function(self, ev, name)
		local tbl = self._byEvent[ev:lower()]
		if not tbl then
			self._editor:echoErr("No such event:", ev)
			return
		end
		for _, entry in ipairs(tbl) do
			if name:find(entry.pattern) then
				command.execute(self._editor, entry.command)
			end
		end
	end,
}

return {
	AutocmdRegistry = AutocmdRegistry,
}
