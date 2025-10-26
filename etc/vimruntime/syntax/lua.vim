syn match luaIdentifier /%w+/

syn keyword luaKeyword local function if for in while then do end return break else elseif or and not
syn keyword luaConstant true false nil

syn match luaOperator "[%+%-%*/%%=<>#]"
syn match luaOperator /~=/
syn match luaDelimiter /[,%.:%(%){}%[%]]/
syn match luaOperator /%.%./
syn match luaKeyword /%.%.%./

syn match luaNumber /%d+/
syn match luaNumber /%d*%.%d+/
syn match luaNumber /0x%x+/

syn match luaString /"[^"]*"/
syn match luaString /%[%[.-%]%]/

syn match luaComment /%-%-.*/
syn match luaComment /%-%-%[%[.-%]%]/

hi def link luaIdentifier Normal
hi def link luaKeyword Statement
hi def link luaConstant Constant
hi def link luaString String
hi def link luaOperator Operator
hi def link luaDelimiter Delimiter
hi def link luaNumber Constant
hi def link luaComment Comment
