" We do this always, to override *.lib wildcard matches
" if exists("b:did_ftplugin")
"   finish
" endif

au BufNewFile,BufRead cds.lib set filetype=cdslib
