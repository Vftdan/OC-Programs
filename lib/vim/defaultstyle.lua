local mapping = {
	normal = {ctermbg = 0, ctermfg = 15, guibg = 0x000000, guifg = 0xFFFFFF},
	cursor = {reverse = true},
	error = {ctermbg = 9, ctermfg = 15, guibg = 0xFF0000, guifg = 0xFFFFFF},
	errormsg = {ctermbg = 1, ctermfg = 15, guibg = 0xFF0000, guifg = 0xFFFFFF},
	todo = {ctermbg = 11, ctermfg = 4, guibg = 0xFFFF00, guifg = 0x0000FF},
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
	search = {ctermbg = 11, ctermfg=4, guifg=0x000060, guibg=0xFFFF00},
	delimiter = "special",
	special = {ctermfg=3, guifg=0xFF8000},
	title = {ctermfg=12, guifg=0x6699FF, reverse=true},  -- Real Vim uses magenta without reversing. This one is from wip.lua instead.
	operator = "statement",
	underlined = {underline = true, ctermfg = 10, guifg = 0x80A080},  -- Real vim uses ctermfg=4, guifg=0x80A0FF, use wip.lua again
	bold = {bold = true, ctermfg = 10, guifg = 0x33CC33},  -- Doesn't exist in real Vim
	italic = {italic = true, reverse=true, ctermfg = 13, guifg = 0xFF50FF},  -- Doesn't exist in real Vim
	bolditalic = {bold = true, italic = true, reverse=true, ctermfg = 8, guifg = 0x337C33, ctermbg = 13, guibg = 0xFFA0FF},  -- Doesn't exist in real Vim
}

return {
	mapping = mapping,
}
