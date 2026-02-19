# Accio

A VS Code-style find and replace sidebar for Neovim.

**Accio** summons a search panel inspired by Visual Studio Code's built-in
search sidebar, bringing familiar find-and-replace UX to Neovim. Built with
plain Neovim split windows and [ripgrep](https://github.com/BurntSushi/ripgrep)
for blazing-fast search — no extra plugin dependencies required.

## Features

- **Search sidebar** - Docked panel with live-as-you-type search
- **Replace** - Inline replace preview with strikethrough old + highlighted new text
- **Replace all** - Apply replacement across all matched files at once
- **Search toggles** - Case sensitive (`Aa`), whole word (`ab`), regex (`.*`) shown in winbar
- **File filters** - "Files to include" and "files to exclude" input fields with glob patterns
- **Collapsible sections** - Toggle replace and filter sections on/off
- **Results tree** - Results grouped by file with match count badges
- **Navigation** - Jump to match in your existing editor window
- **Powered by ripgrep** - Fast, respects `.gitignore`, full regex support

## Requirements

- Neovim >= 0.10
- [ripgrep](https://github.com/BurntSushi/ripgrep) >= 14

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "maureyesdev/accio.nvim",
  keys = {
    { "<C-S-h>", function() require("accio").toggle() end, desc = "Toggle search panel" },
  },
  opts = {},
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Accio` | Open the search panel |
| `:AccioToggle` | Toggle the search panel |
| `:AccioClose` | Close the search panel |

### Keymaps (in search panel)

| Key | Context | Action |
|-----|---------|--------|
| `<Tab>` / `<S-Tab>` | Any | Focus next / previous pane |
| `<C-j>` / `<C-n>` | Any | Focus next pane |
| `<C-k>` / `<C-p>` | Any | Focus previous pane |
| `<M-s>` | Any | Toggle case sensitive |
| `<M-w>` | Any | Toggle whole word |
| `<M-r>` | Any | Toggle regex |
| `<M-c>` | Any | Toggle replace section |
| `<M-f>` | Any | Toggle file filter section |
| `<CR>` | Results | Jump to match in editor |
| `R` | Any | Replace all matches |
| `q` | Any | Close panel |

### Search Panel Layout

```
+---------------------------------------+
|  Search               Aa  ab  .*      |  ← winbar with toggle indicators
+---------------------------------------+
|  Search query...                      |
+---------------------------------------+
|  Replace text...                      |  ← toggle with <M-c>
+---------------------------------------+
|  Files to include...                  |  ← toggle with <M-f>
+---------------------------------------+
|  Files to exclude...                  |
+---------------------------------------+
|  4 results in 2 files                 |
|                                       |
|    init.lua                      [2]  |
|      7: matched content here          |
|      12: another match                |
|                                       |
|    theme.lua                     [2]  |
|      3: first match                   |
|      8: second match                  |
+---------------------------------------+
```

The **search input winbar** shows the active flag toggles on the right:
- `Aa` — case sensitive (highlighted when active)
- `ab` — whole word
- `.*` — regex mode

All Accio buffers use `filetype = "accio"`, so you can target them in your
own autocommands to customize `winbar`, `statusline`, or other options:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "accio",
  callback = function()
    -- e.g. disable your global winbar plugin for accio windows
  end,
})
```

## Configuration

```lua
require("accio").setup({
  -- Sidebar position: "left" or "right"
  position = "left",

  -- Sidebar width (columns)
  width = 40,

  -- Path to ripgrep binary
  rg_path = "rg",

  -- Debounce delay (ms) before triggering search
  debounce = 150,

  -- Auto-focus search input on open
  auto_focus = true,

  -- Show replace section expanded by default
  replace_expanded = false,

  -- Show file filter section expanded by default
  filters_expanded = false,
})
```

## Health Check

Run `:checkhealth accio` to verify your setup — it will check your Neovim
version and confirm ripgrep is installed and accessible.

## Inspiration

- [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim) - Buffer-based find and replace
- VS Code's built-in search sidebar

## License

MIT
