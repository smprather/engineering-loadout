" Only do this when not done yet for this buffer
if exists("b:did_ftplugin")
  finish
endif

au BufNewFile,BufRead *.lib set filetype=liberty
" cdslib type is a special case of *.lib!
au BufNewFile,BufRead cds.lib set filetype=cdslib
