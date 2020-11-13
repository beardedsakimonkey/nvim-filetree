if get(g:, 'loaded_filetree') is 1
    finish
endif
let g:loaded_filetree = 1

fu s:isdir(dir)
    return !empty(a:dir) && isdirectory(a:dir)
endf

aug filetree | au!
    au BufEnter * if <SID>isdir(expand('%')) | Filetree | endif
aug END

hi default link FiletreeDirectory      Directory
hi default link FiletreeDirectorySlash Comment
hi default link FiletreeExecutable     PreProc
hi default link FiletreeSymlink        Constant
hi default link FiletreeNumber         Comment

com! -bar Filetree lua require'filetree'.start()<cr>
