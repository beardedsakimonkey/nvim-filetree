if exists('b:did_ftplugin')
    finish
end
let b:did_ftplugin = 1

setl cursorline
setl nofoldenable
setl nonumber
setl buftype=nofile
setl nomodifiable

setl list
setl listchars=tab:\|\ 
setl noexpandtab
setl tabstop=4
setl shiftwidth=4
setl softtabstop=0
