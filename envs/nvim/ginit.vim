" Enable Mouse
set mouse=a

" System clipboard — yank/paste use + register by default; also mirror to *
" (PRIMARY selection) for apps that support it.
set clipboard=unnamed,unnamedplus

" Auto-copy visual selection to system clipboard on mouse release.
" Mimics X11 primary-selection behavior using the CLIPBOARD register instead,
" since WSLg's XWayland does not reliably bridge PRIMARY to Windows clipboard.
vnoremap <LeftRelease> "+y

" Set Editor Font
if exists(':GuiFont')
    " Use GuiFont! to ignore font errors
    GuiFont Hack Nerd Font Mono:h10
endif

" Disable GUI Tabline
if exists(':GuiTabline')
    GuiTabline 0
endif

" Disable GUI Popupmenu
if exists(':GuiPopupmenu')
    GuiPopupmenu 0
endif

" Enable GUI ScrollBar
if exists(':GuiScrollBar')
    GuiScrollBar 1
endif

" Right Click Context Menu (Copy-Cut-Paste)
nnoremap <silent><RightMouse> :call GuiShowContextMenu()<CR>
inoremap <silent><RightMouse> <Esc>:call GuiShowContextMenu()<CR>
xnoremap <silent><RightMouse> :call GuiShowContextMenu()<CR>gv
snoremap <silent><RightMouse> <C-G>:call GuiShowContextMenu()<CR>gv
