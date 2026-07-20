" Only load this indent file when no other was loaded.
if exists("b:did_indent")
  finish
endif
let b:did_indent = 1

" No indent rules for cdslib!
setlocal noautoindent
setlocal nocindent
setlocal nosmartindent
setlocal indentexpr=
