" Enable Mouse
set mouse=a

" System clipboard — yank/paste use + register by default; also mirror to *
" (PRIMARY selection) for apps that support it.
set clipboard=unnamed,unnamedplus

" Mouse-drag → auto-copy to clipboard + return cursor to pre-click position.
" <LeftMouse> fires before vim moves the cursor so we capture the original pos.
" <Cmd> avoids command-line mode flicker (nvim-only).
let g:pre_mouse_pos = [0, 1, 1, 0]
nnoremap <LeftMouse> <Cmd>let g:pre_mouse_pos = getpos('.')<CR><LeftMouse>
vnoremap <LeftRelease> "+y<Cmd>call setpos('.', g:pre_mouse_pos)<CR>

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

