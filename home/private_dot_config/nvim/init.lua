-- nvim here is the terminal editor for quick fixes, the IDE work is in
-- JetBrains and Sublime: options only, no plugin manager to install and
-- keep in step on two machines.

vim.g.mapleader = " "

-- yank and put go through the system clipboard (wl-copy here, pbcopy on
-- the mac), so a `y` in nvim pastes into the browser and back
vim.o.clipboard = "unnamedplus"

-- no .swp litter next to files that are synced; undo survives instead
vim.o.swapfile = false
vim.o.backup = false
vim.o.undofile = true

vim.o.mouse = "a"
vim.o.number = true
vim.o.cursorline = true
vim.o.scrolloff = 4
vim.o.wrap = false
vim.o.termguicolors = true
vim.o.splitright = true
vim.o.splitbelow = true

-- search: case-insensitive until the pattern has a capital
vim.o.ignorecase = true
vim.o.smartcase = true

-- four spaces, as in the scripts of this repo; Makefiles keep their tabs
-- through the stock ftplugin
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.softtabstop = 4
