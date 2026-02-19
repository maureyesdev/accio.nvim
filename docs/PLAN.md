# Accio - Development Plan

## Vision

A VS Code-style find and replace **sidebar panel** for Neovim, built on top of
`snacks.nvim` for window/layout management and `ripgrep` for search.

---

## Architecture Overview

```
lua/accio/
  init.lua          -- setup(), open(), toggle(), close()
  config.lua        -- Default config + user merge
  state.lua         -- Central state: query, flags, results
  actions.lua       -- Replace, replace-all, open-file, etc.
  highlights.lua    -- Highlight group definitions
  ui/
    layout.lua      -- Snacks.layout sidebar composition
    input.lua       -- Search/Replace/Filter input buffers
    toggles.lua     -- Aa, ab, .* toggle indicators (virtual text)
    results.lua     -- Results tree rendering (extmarks + virtual text)
  engine/
    ripgrep.lua     -- rg --json subprocess via jobstart/jobstop
    parser.lua      -- Parse rg JSON output into structured data
plugin/
  accio.lua         -- :Accio, :AccioToggle commands
```

### Key Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Window system | Snacks.layout + Snacks.win | Composable sidebar with multiple panes |
| Search backend | ripgrep `--json` | Structured output, fast, ubiquitous |
| Result rendering | Extmarks + virtual text | Rich formatting, foldable, navigable |
| State management | Single Lua table per instance | Simple, no external deps |

### Sidebar Layout (Mirrors VS Code)

```
+--------------------------------------+
| SEARCH                    [icons]    |  <- Title bar
+--------------------------------------+
| Search (Aa for history)   Aa ab .*   |  <- Search input + toggles
+--------------------------------------+
| v  Replace                AB  ab/ac  |  <- Replace input (collapsible)
+--------------------------------------+
| files to include       e.g. *.ts     |  <- Include filter input
+--------------------------------------+
| files to exclude                     |  <- Exclude filter input
+--------------------------------------+
| 4 results in 3 files                 |  <- Status line
|                                      |
| v  init.lua              7, M    (1) |  <- File header (foldable)
|      vim.cmd("colorscheme rose-pi... |    <- Match line
|                                      |
| v  lazy-lock.json          M     (1) |
|      "rose-pine": { "branch": "ma... |
|                                      |
| v  theme.lua    lua/plugins      (2) |
|      "rose-pine/neovim",             |
|      name = "rose-pine",             |
+--------------------------------------+
```

---

## Phase 1: Core Skeleton & Sidebar Shell

**Goal**: Open/close a sidebar panel with all input fields visible.

### Tasks

1. **`config.lua`** - Default options:
   - `width` (sidebar width, default 40)
   - `position` ("left" or "right", default "left")
   - `keymaps` (toggle sidebar, navigation)
   - `rg_path` (ripgrep binary, default "rg")
2. **`ui/layout.lua`** - Snacks.layout with vertical box:
   - Title bar ("SEARCH")
   - Search input (Snacks.win, single-line editable buffer)
   - Replace input (Snacks.win, single-line, collapsible via chevron)
   - Files to include input (Snacks.win, single-line, placeholder text)
   - Files to exclude input (Snacks.win, single-line, placeholder text)
   - Results pane (Snacks.win, read-only buffer, fills remaining space)
3. **`init.lua`** - Public API: `setup(opts)`, `open()`, `close()`, `toggle()`
4. **`plugin/accio.lua`** - Vim commands: `:Accio`, `:AccioToggle`
5. **Keymaps** - `<C-S-h>` or configurable to toggle sidebar

### Milestone

Run `:Accio` and see a left sidebar with "SEARCH" header, search input,
collapsed replace, include/exclude filter fields, and empty results area.

---

## Phase 2: Search Engine Integration

**Goal**: Type in search field, see live results from ripgrep.

### Tasks

1. **`engine/ripgrep.lua`** - Spawn `rg --json` via `vim.fn.jobstart()`:
   - Build rg command from state (pattern, flags, paths, globs)
   - Stream stdout line-by-line via `on_stdout`
   - Handle stderr (errors/warnings)
   - Debounce: re-run after 150ms of no typing
   - Abort: `vim.fn.jobstop()` previous job on new search
2. **`engine/parser.lua`** - Parse rg `--json` output lines into:
   ```lua
   { type = "match", file = "...", lnum = N, col = N, text = "...", match_text = "..." }
   { type = "end", stats = { files_matched = N, matches = N } }
   ```
3. **`state.lua`** - Central state table:
   - `query` (search string)
   - `replacement` (replace string)
   - `flags` { case_sensitive, whole_word, regex }
   - `include_glob` (files to include pattern)
   - `exclude_glob` (files to exclude pattern)
   - `results` (parsed match list, grouped by file)
   - `status` (idle | searching | error)
4. **Wire inputs** - `TextChanged`/`TextChangedI` autocmds on search input
   buffer to trigger debounced search
5. **Wire file filters** - Include/exclude inputs map to rg `--glob` and
   `--glob !` flags; changes re-trigger search

### Milestone

Type "foo" in search → results appear in results pane grouped by file.
Type "*.lua" in files to include → only Lua matches shown.

---

## Phase 3: Results Tree Display

**Goal**: Rich results display matching VS Code's tree format.

### Tasks

1. **`ui/results.lua`** - Render results buffer:
   - Status line: "N results in M files"
   - File headers: icon + filename + relative path + match count badge
   - Match lines: line content with highlighted match region
   - Foldable file groups (extmarks + concealed fold markers)
2. **`highlights.lua`** - Define highlight groups:
   - `AccioMatch` - search match highlight (yellow/orange background)
   - `AccioFile` - file name (bold)
   - `AccioFilePath` - relative path (dimmed)
   - `AccioLineNr` - line number
   - `AccioMatchCount` - count badge
   - `AccioStatus` - status line text
   - `AccioReplace` - replacement preview (green)
   - `AccioStrikethrough` - old text strikethrough (red)
3. **Navigation keymaps** in results buffer:
   - `<CR>` - go to file/line in editor
   - `<C-v>` - open in vsplit
   - `<C-x>` - open in hsplit
   - `j/k` - move between matches
   - `zo/zc` - fold/unfold file groups
   - `zM/zR` - fold/unfold all

### Milestone

Search shows a VS Code-style tree of results grouped by file, with
highlighted matches and count badges. Enter jumps to the match location.

---

## Phase 4: Toggle Buttons & Filters

**Goal**: Case sensitivity, whole word, regex toggles in the search input.

### Tasks

1. **`ui/toggles.lua`** - Render toggle indicators:
   - `Aa` (case sensitive) - right-aligned virtual text in search input
   - `ab` (whole word)
   - `.*` (regex mode)
   - Visual states: active (highlighted) vs inactive (dimmed)
   - `AB` (preserve case) - in replace input
2. **Toggle keymaps** (while in search input buffer):
   - `<M-c>` - toggle case sensitive (`rg -s` / `rg -i`)
   - `<M-w>` - toggle whole word (`rg -w`)
   - `<M-r>` - toggle regex mode (default) vs fixed string (`rg -F`)
3. **Include/Exclude filter behavior**:
   - Include field: maps to `rg --glob <pattern>` (e.g. `*.ts, src/**/include`)
   - Exclude field: maps to `rg --glob !<pattern>`
   - Support comma-separated multiple patterns
   - Placeholder text as virtual text (disappears on focus)
4. **Chevron toggle** - `>` / `v` to expand/collapse replace + filter section

### Milestone

Toggle case sensitivity and see results update live. Type `*.lua` in
include field to filter. Collapse/expand the replace section.

---

## Phase 5: Replace Functionality

**Goal**: Replace individual matches, per-file, or all.

### Tasks

1. **Replace input** - Collapsible section toggled by chevron (`>` / `v`)
2. **Inline replace preview** in results:
   - Strikethrough on original match text (~~old~~)
   - Highlighted replacement text next to it (new)
   - Uses extmarks with `virt_text` for inline display
3. **Replace actions**:
   - Replace single match (icon/button per match line)
   - Replace all in file (icon/button per file header)
   - Replace all global (button in title bar area)
4. **File I/O** - Read file, apply replacements, write back
5. **Confirmation dialog** for replace-all (configurable)
6. **Undo integration** - Each replace-all creates a single undo point
   per affected buffer (for buffers already open)

### Milestone

Search → type replacement → see inline preview (strikethrough old +
highlighted new) → replace all → all files updated → undo reverts.

---

## Phase 6: Polish & Advanced Features

**Goal**: Production-quality UX.

### Tasks

1. **Search history** - `<Up>`/`<Down>` in search input cycles history
2. **Preserve state on reopen** - Remember last query, filters, toggles
3. **Resize** - Configurable sidebar width
4. **Performance** - Large result sets: limit display + "show more" prompt
5. **Statusline integration** - Show active search count
6. **Which-key hints** - Register keymaps with descriptions
7. **Health check** - `:checkhealth accio` validates rg is installed
8. **Documentation** - `doc/accio.txt` vimdoc help file

---

## File Structure (Final)

```
accio/
  lua/
    accio/
      init.lua
      config.lua
      state.lua
      actions.lua
      highlights.lua
      health.lua
      ui/
        layout.lua
        input.lua
        toggles.lua
        results.lua
      engine/
        ripgrep.lua
        parser.lua
  plugin/
    accio.lua
  doc/
    accio.txt
  docs/
    PLAN.md
  stylua.toml
  README.md
  LICENSE
```

---

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| Neovim >= 0.10 | Yes | Extmarks, Lua API |
| ripgrep >= 14 | Yes | Search backend |
| snacks.nvim | Yes | Window/layout management |
| nvim-web-devicons | Optional | File icons in results |

---

## Session Continuity

To resume from any new Claude Code session:

1. **MEMORY.md** is auto-loaded every session with project context
2. **This PLAN.md** is the authoritative roadmap
3. **Git history** shows exactly what code exists

### Resume Prompt

```
Read docs/PLAN.md and continue building accio from where we left off.
```
