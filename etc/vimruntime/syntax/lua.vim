syn match luaIdentifier /%w+/

" TODO somehow prevent the keywords being matched as a prefix
syn match luaKeyword /local/
syn match luaKeyword /function/
syn match luaKeyword /if/
syn match luaKeyword /for/
syn match luaKeyword /in/
syn match luaKeyword /while/
syn match luaKeyword /then/
syn match luaKeyword /do/
syn match luaKeyword /end/
syn match luaKeyword /return/
syn match luaKeyword /break/
syn match luaKeyword /else/
syn match luaKeyword /elseif/
syn match luaKeyword /or/
syn match luaKeyword /and/
syn match luaKeyword /not/

syn match luaOperator "[%+%-%*/%%=<>#]"
syn match luaOperator /~=/
syn match luaDelimiter /[,%.:%(%){}%[%]]/
syn match luaOperator /%.%./
syn match luaKeyword /%.%.%./

syn match luaNumber /0x%d+/
syn match luaNumber /%d+/
syn match luaNumber /%d*%.%d+/

syn match luaString /"[^"]*"/
syn match luaString /%[%[.-%]%]/

syn match luaComment /%-%-.*/
syn match luaComment /%-%-%[%[.-%]%]/

hi def link luaIdentifier Normal
hi def link luaKeyword Statement
hi def link luaString String
hi def link luaOperator Operator
hi def link luaDelimiter Delimiter
hi def link luaNumber Constant
hi def link luaComment Comment
