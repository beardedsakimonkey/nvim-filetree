if 'filetree' !=# get(b:, 'current_syntax', 'filetree')
    finish
endif

if !exists('b:current_syntax')
    syntax match FiletreeNumber         "^\s*\d\+"
    syntax match FiletreeDirectory      "\D\+\ze\/$"
    syntax match FiletreeDirectorySlash "\/$"
    syntax match FiletreeExecutable     "[^\*]\+\*$"
    syntax match FiletreeSymlink        "[^@]\+@$"
endif

let b:current_syntax = 'filetree'
