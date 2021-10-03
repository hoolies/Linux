syntax on
set nocompatible

"   Plugs
call plug#begin()

    Plug 'SirVer/ultisnips'
    Plug 'honza/vim-snippets'
    Plug 'neoclide/coc.nvim'
    Plug 'davidhalter/jedi-vim'

    Plug 'ncm2/ncm2'
    Plug 'HansPinckaers/ncm2-jedi'
    Plug 'roxma/nvim-yarp'
    Plug 'ncm2/ncm2-bufword'
    Plug 'ncm2/ncm2-path'
    
    Plug 'majutsushi/tagbar'
    
    Plug 'Vimjas/vim-python-pep8-indent'
    
    Plug 'lervag/vimtex'
    Plug 'Konfekt/FastFold'
    Plug 'matze/vim-tex-fold'
    
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    
    Plug 'vim-airline/vim-airline'
    
    Plug 'w0rp/ale'

    Plug 'Chiel92/vim-autoformat'
    
    Plug 'scrooloose/nerdtree'
    Plug 'tiagofumo/vim-nerdtree-syntax-highlight'

call plug#end()



filetype plugin indent on
filetype plugin on



"       Settings

set fileformat=unix

set showmatch
set ignorecase
set smartcase
set wrapscan 
set hlsearch
set incsearch
set cpoptions+=x

set tabstop=4
set softtabstop=4
set expandtab
set shiftwidth=4
set autoindent
set number
set wildmode=longest,list
set cc=0
set mouse=v
set clipboard=unnamedplus
set cursorcolumn
    hi CursorColumn cterm=NONE ctermbg=234 ctermfg=NONE
set cursorline
    hi CursorLine cterm=NONE ctermbg=234 ctermfg=NONE
set ttyfast
set spell
set visualbell

set undodir=~/.config/nvim/undodir
set undofile
set undolevels=10000
set undoreload=100000

set noshowmode
set noshowcmd




if has("autocmd")
    au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$")
                \| exe "normal! g'\"" | endif
endif

autocmd BufEnter * call ncm2#enable_for_buffer()
set completeopt=noinsert,menuone
set shortmess+=c



"   Mappings

inoremap <A-j> <Esc>:m .+1<CR>==gi
inoremap <A-k> <Esc>:m .-2<CR>==gi
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv" move split panes to left/bottom/top/right
nnoremap <A-h> <C-W>H
nnoremap <A-j> <C-W>J
nnoremap <A-k> <C-W>K
nnoremap <A-l> <C-W>L" move between panes to left/bottom/top/right
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap gf :vert winc f<cr>" copies filepath to clipboard by pressing yf
:nnoremap <silent> yf :let @+=expand('%:p')<CR>
:nnoremap <silent> yd :let @+=expand('%:p:h')<CR>" Vim jump to the last position when reopening a file

:inoremap ii <Esc>
:inoremap jk <Esc>
:inoremap kj <Esc>
:vnoremap jk <Esc>

nnoremap S diw"0P
nnoremap cc "_cc
nnoremap q: :q<CR>
nnoremap w: :w<CR>

nnoremap x "_x
vnoremap x "_x

set clipboard=unnamedplus


map <C-n> :NERDTreeToggle<CR>




"   NCM2
augroup NCM2

    autocmd Filetype tex call ncm2#register_source ({
        \ 'name': 'vimtex',
        \ 'priority': 8,
        \ 'scope': ['tex'],
        \ 'mark': 'tex',
        \ 'word_pattern': '\w',
        \ 'complete_pattern': g:vimtex#re#ncm2,
        \ 'on_complete': ['ncm2#on_complete#omni', 'vimtex#complete#omnifunc'],
        \ })
augroup END

let ncm2#popup_delay = 5
let ncm2#compete_length = [[1,1]]
let g:ncm2#matcher = 'substrfuzzy'



"   VimTex
let g:tex_flavor = 'latex'
let g:tex_conceal = ''
let g:vimtex_fold_manual = 1
let g:vimtex_compiler_programe = 'nvr'
let g:vimtex_compiler_latexmk = {
            \ 'continuous' : 1,
            \}
let g:vimtex_view_general_viewer='chrome'

"   Ale
let g:ale_lint_on_enter = 0
let g:ale_lint_on_text_changed = 'never'
let g:ale_echo_msg_error_str = 'E'
let g:ale_echo_msg_warning_str = 'W'
let g:ale_echo_msg_format = '[%linter%] %s [%severity%]'
let g:ale_linters = {'python': ['flake8']}

"   Airline
let g:airline_left_sep = ''
let g:airline_right_sep = ''
let g:airline#extensions#ale#anabled =1
let airline#extensions#ale#error_symbol = 'E:'
let airline#extensions#ale#warning_symbol = 'W:'

"   Python
let g:python3_host_prog = '/usr/bin/python3'
let g:python_host_prog = '/usr/bin/python2'
