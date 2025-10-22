local mapping = {
	normal = {ctermbg = 0, ctermfg = 15, guibg = 0x000000, guifg = 0xFFFFFF},
	cursor = {reverse = true},
	error = {ctermbg = 9, ctermfg = 15, guibg = 0xFF0000, guifg = 0xFFFFFF},
	errormsg = {ctermbg = 1, ctermfg = 15, guibg = 0xFF0000, guifg = 0xFFFFFF},
	todo = {ctermbg = 11, ctermfg = 0, guibg = 0xFFFF00, guifg = 0x0000FF},
	statement = {ctermfg = 11, guifg = 0xFFFF60},
	preproc = {ctermfg = 13, guifg = 0xFF80FF},
	visual = {ctermbg = 8, guibg = 0x6C6C6C},
	string = "constant",
	constant = {ctermfg = 13, guifg = 0xFFA0A0},
	comment = {ctermfg = 14, guifg = 0x80A0FF},
	endofbuffer = "nontext",
	nontext = {ctermfg = 12, guifg = 0x0000FF},
	linenr = {ctermfg = 11, guifg = 0xFFFF00},
	statusline = {reverse = true},
}

return {
	mapping = mapping,
}
