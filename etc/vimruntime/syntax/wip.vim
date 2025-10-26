" Space characters inside patterns currently need to be escaped with backslashes
" Pattern character are escaped with percents, because these are Lua patterns
syn match wipH1 /^#.*/ keepend excludenl
syn match wipH2 /^##.*/ keepend excludenl
syn match wipPageTitle /^&.*/ keepend excludenl
syn match wipItalic /%*[^%*]*%*/

hi wipH1 cterm=bold,underline gui=bold,underline ctermfg=10 guifg=#33CC33
hi wipH2 cterm=underline gui=underline ctermfg=10 guifg=#80a080
hi def link wipPageTitle Title
hi wipItalic cterm=italic,reverse gui=italic,reverse ctermfg=13 guifg=#FF50FF
