" Space characters inside patterns currently need to be escaped with backslashes
" Pattern character are escaped with percents, because these are Lua patterns
syn match wipH1 /^#.*/ keepend excludenl
syn match wipH2 /^##.*/ keepend excludenl
syn match wipPageTitle /^&.*/ keepend excludenl
syn match wipItalic /%*[^%*]*%*/

hi def link wipH1 Bold
hi def link wipH2 Underlined
hi def link wipPageTitle Title
hi def link wipItalic Italic
