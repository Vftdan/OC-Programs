syn region markdownSection matchgroup=markdownHeadingDelimiter start=/^#+%s*/ end=/$/
syn match markdownListMarker /^%s*%-%s/
syn match markdownOrderedListMarker /^%s*%d+%.%s/
syn match markdownTaskMarker /^%s*%-%s*%[[%sX]%]%s/
syn match markdownItalic /%*[^%*%s].-%*/
syn match markdownItalic /_[^_%s].-_/
syn match markdownBold /%*%*[^%*%s].-%*%*/
syn match markdownBold /__[^_%s].-__/
syn match markdownBoldItalic /%*%*%*[^%*%s].-%*%*%*/
syn match markdownBoldItalic /___[^_%s].-___/
syn region markdownUrl matchgroup=markdownLink start=/%[[^%[]*%]%(/ end=/%)/
syn match markdownBlockquote /^%s*>[%s>]*/
syn region markdownCode matchgroup=markdownCodeDelimiter start=/^```/ end=/^```/

hi def link markdownSection Title
hi def link markdownHeadingDelimiter Delimiter
hi def link markdownListMarker Statement
hi def link markdownOrderedListMarker Statement
hi def link markdownTaskMarker Statement
hi def link markdownItalic Italic
hi def link markdownBold Bold
hi def link markdownBoldItalic BoldItalic
hi def link markdownLink Underlined
hi def link markdownUrl String
hi def link markdownBlockquote Comment
hi def link markdownCodeDelimiter Delimiter
