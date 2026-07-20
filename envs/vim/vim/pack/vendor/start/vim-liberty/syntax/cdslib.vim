" Vim syntax file
" Language:     cds.lib definition
" Maintainer:   Peter Debacker "pdback@imec.be"
" Last Change:  06/08/2014
"
" This is loosely based on spectre .vim by Ahmed Nabil

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

" Syntax is case INsensitive
syn case ignore
setlocal iskeyword=@,48-57,_

syn keyword     cdslibTodo        contained TODO XXX FIXME NOTE

" Main statements
"===============================================
syn keyword     cdslibStatement       DEFINE nextgroup=cdslibLib skipwhite
syn region      cdslibLib start="\S" end="\s" skipwhite contained keepend nextgroup=cdslibArg

syn keyword     cdslibStatement       INCLUDE SOFTINCLUDE UNDEFINE nextgroup=cdslibArg skipwhite
syn region      cdslibArg start="\S" end="$" skipwhite contained keepend contains=cdslibVar

syn region cdslibComment  start=/#/ end=/$/ contains=cdslibTodo display oneline
syn region cdslibComment  start=/--/ end=/$/ contains=cdslibTodo display oneline
"syn region cdslibString   start=/"/ end=/"/ contains=cdslibVar contained
"syn region cdslibString   start=/'/ end=/'/ contains=cdslibVar contained
syn match  cdslibVar      "\$\%(\k\+\|\d\)"

syn region cdslibComment start="/\*" end="\*/" contains=cdslibTodo

" Syncs
" =====
syn sync minlines=10

" Define the default highlighting.
" For version 5.7 and earlier: only when not done already
" For version 5.8 and later: only when an item doesn't have highlighting yet
if version >= 508 || !exists("did_cdslib_syntax_inits")
  if version < 508
    let did_cdslib_syntax_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif

  HiLink cdslibTodo             Todo
  HiLink cdslibComment          Comment
  HiLink cdslibString           String
  HiLink cdslibStatement        Keyword
  HiLink cdslibVar              Identifier
  HiLink cdslibArg              String
  HiLink cdslibLib              Define

  delcommand HiLink
endif

let b:current_syntax = "cdslib"

" TODO
" insert the following to $VIM/syntax/scripts.vim
" to autodetect HSpice netlists and text listing output:
"
" " Spice netlists and text listings
" elseif getline(1) =~ 'cdslib\>' || getline("$") =~ '^\.end'
"   so <sfile>:p:h/cdslib.vim

