local makeClass = require("vim.makeclass")

local BooleanOption = makeClass {
	init = function(self, name, setCallback, getCallback)
		self.name = name
		self._setCallback = setCallback
		self._getCallback = getCallback
	end,
	disable = function(self, editor, opts)
		opts = opts or {}
		self._setCallback(editor, false, {scope = opts.scope, name = self.name})
	end,
	enable = function(self, editor, opts)
		opts = opts or {}
		self._setCallback(editor, true, {scope = opts.scope, name = self.name})
	end,
	toggle = function(self, editor, opts)
		opts = opts or {}
		local oldValue = self._getCallback(editor, {scope = opts.scope, name = self.name})
		if oldValue ~= nil then
			self._setCallback(editor, not oldValue, {scope = opts.scope, name = self.name})
		end
	end,
	set = function(self, editor, opts)
		opts = opts or {}
		local value = opts.value
		if type(value) == "string" then
			value = value:lower()
			if value == "true" or value == self.name then
				value = true
			elseif value == "false" or value == "no" .. self.name then
				value = false
			else
				editor:echoErr(("Invalid argument: %s=%s"):format(self.name, value))
				return
			end
		end
		self._setCallback(editor, not not value, {scope = opts.scope, name = self.name})
	end,
	query = function(self, editor, opts)
		opts = opts or {}
		local value = self._getCallback(editor, {scope = opts.scope, name = self.name})
		if value ~= nil then
			if value then
				editor:echo(("%s=%s"):format(self.name, self.name))
			else
				editor:echo(("%s=no%s"):format(self.name, self.name))
			end
		end
	end,
}

local StringOption = makeClass {
	init = function(self, name, setCallback, getCallback)
		self.name = name
		self._setCallback = setCallback
		self._getCallback = getCallback
	end,
	set = function(self, editor, opts)
		opts = opts or {}
		local value = opts.value
		self._setCallback(editor, value, {scope = opts.scope, name = self.name})
	end,
	query = function(self, editor, opts)
		opts = opts or {}
		local value = self._getCallback(editor, {scope = opts.scope, name = self.name}) or ""
		editor:echo(("%s=%s"):format(self.name, value))
	end,
	add = function(self, editor, opts)
		opts = opts or {}
		local value = self._getCallback(editor, {scope = opts.scope, name = self.name}) or ""
		value = value .. opts.value
		self._setCallback(editor, value, {scope = opts.scope, name = self.name})
	end,
}

local options = {
	hlsearch = BooleanOption("hlsearch", function(editor, value, opts)
		editor.triggerHlsearch = value
	end, function(editor, opts)
		return editor.triggerHlsearch
	end),
	syntax = StringOption("syntax", function(editor, value, opts)
		local buf = editor:getCurrentBuffer()
		if not buf then
			return
		end
		buf.syntaxName = value
		buf.syntaxRegistry:clear()
		require("vim.command").runtimeFile(editor, ("syntax/%s.vim"):format(value))
	end, function(editor, opts)
		local buf = editor:getCurrentBuffer()
		if not buf then
			return nil
		end
		return buf.syntaxName
	end),
}

options.hl = options.hlsearch
options.syn = options.syntax

return {
	options = options,
}
