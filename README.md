# noah-inkscape

A macOS figure-workflow layer around **Inkscape + Neovim + LaTeX**, with
Hammerspoon handling the parts that need application-aware keyboard automation.

The normal figure lifecycle is:

```text
Neovim
  → create / fuzzy-search a figure
  → choose a visual template
  → Inkscape opens the SVG
  → save the SVG while drawing
  → PDF + pdf_tex are regenerated automatically
  → close the Inkscape document
  → its watcher is terminated automatically
  → compile from LaTeX
  → reopen the SVG later from the visual figure picker
```

The editable **`.svg` is always the source of truth**. The `.pdf` and
`.pdf_tex` files are generated outputs for LaTeX.

This repository is deliberately macOS-oriented. It uses `/bin/zsh`, `open -a`,
Hammerspoon, iTerm2, and macOS's `md5` command.

---

## Contents

- [Features](#features)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Installation](#installation)
  - [1. Download the repository](#1-download-the-repository)
  - [2. Install runtime dependencies](#2-install-runtime-dependencies)
  - [3. Make the scripts executable](#3-make-the-scripts-executable)
  - [4. Install the Neovim module](#4-install-the-neovim-module)
  - [5. Install the Hammerspoon modules](#5-install-the-hammerspoon-modules)
  - [6. Configure the iTerm2 LaTeX popup profile](#6-configure-the-iterm2-latex-popup-profile)
  - [7. Install the Inkscape palettes](#7-install-the-inkscape-palettes)
- [Neovim workflow](#neovim-workflow)
- [Automatic export and watcher lifecycle](#automatic-export-and-watcher-lifecycle)
- [Non-exporting guide layer](#non-exporting-guide-layer)
- [Visual previews](#visual-previews)
- [Inkscape style mode](#inkscape-style-mode)
- [Engineering symbol library](#engineering-symbol-library)
- [LaTeX label popup](#latex-label-popup)
- [Templates](#templates)
- [Palettes](#palettes)
- [LaTeX integration](#latex-integration)
- [Standalone scripts](#standalone-scripts)
- [Temporary files and caches](#temporary-files-and-caches)
- [Troubleshooting](#troubleshooting)
- [Updating](#updating)
- [Uninstalling](#uninstalling)

---

# Features

## Figure creation from Neovim

The plugin finds the current **VimTeX project root**, creates/uses its
`figures/` directory, copies an SVG template into it, opens the figure in
Inkscape, and inserts the corresponding LaTeX figure block into the source
buffer.

Commands:

```vim
:Figure
:FigureNew
:FigureNew beam_fbd
```

`Figure` is the main entry point. It opens a Telescope picker containing:

- `+ New figure…`
- every existing `figures/**/*.svg`
- a live visual preview of the selected SVG

When creating a figure, the next Telescope picker shows the available templates
with visual previews as well.

## Automatic PDF + LaTeX export

Opening a figure through this workflow starts one watcher for that SVG.

The watcher:

1. performs an initial export;
2. watches the SVG with `fswatch`;
3. re-exports after saves;
4. produces both `figure.pdf` and `figure.pdf_tex`.

## Automatic watcher cleanup

Hammerspoon watches Inkscape's document windows. Each `watch_figure` process
registers the SVG path and its PID under `$TMPDIR/noah-inkscape/`.

When the matching Inkscape document window disappears, Hammerspoon sends the
watcher a `TERM`. The watcher then explicitly terminates its child `fswatch`
process and removes its lifecycle files.

This prevents the accumulation of detached `fswatch` processes after figures
are closed.

## Working-only guide layer

`export_figure` never exports directly from the editable SVG. It creates a
temporary SVG beside the source, removes the working guide layer from that
copy, and exports the copy.

The default excluded layer is:

```text
10 - GUIDES
```

Matching is case-insensitive and normalizes common dash characters, so the
current template layer:

```text
10 – Guides
```

is excluded too.

The source SVG is not altered.

## Visual previews

There are three visual picker paths:

- **Figure picker:** Telescope + rendered SVG thumbnail
- **Template picker:** Telescope + rendered SVG thumbnail
- **Symbol picker:** Hammerspoon chooser + image in each symbol row

Figure/template previews are cached and only regenerated when the SVG changes.

## Composable Inkscape styles

Hammerspoon provides a deliberate, toggleable **style mode**. Individual keys
only modify one style dimension, so width, dash pattern, and arrow marker can
be applied successively.

Example:

```text
'   enter style mode
h   heavy
:   light-dashed
f   force arrow
'   leave style mode
```

## Engineering symbols

The Hammerspoon symbol chooser fuzzy-searches reusable SVG symbols. `Shift+S`
opens it anywhere in Inkscape, independent of style mode. Press Enter to insert
ordinary editable SVG geometry, or Shift+Enter to open the selected symbol's
source sheet.

It can also capture the current Inkscape selection and save it as a new symbol,
optionally inside a category such as:

```text
supports/fixed_support

dynamics/spring
```

## Neovim LaTeX label popup

`Shift+T` in Inkscape opens a small, dedicated iTerm2 hotkey window containing
Neovim. The editor uses the normal TeX filetype and can load the user's normal
LuaSnip configuration.

It supports both:

- creating a new raw LaTeX label;
- editing a selected simple one-line Inkscape text label.

Press **Enter** to accept or **Ctrl-C** to cancel.

The text seen inside Inkscape is an approximate visual placeholder. Final text
is typeset through Inkscape's PDF+LaTeX export.

---

# Repository layout

```text
noah-inkscape/
├── hammerspoon/
│   ├── inkscape_latex.lua
│   ├── inkscape_styles.lua
│   ├── inkscape_symbols.lua
│   └── inkscape_watchers.lua
├── nvim/
│   └── lua/
│       └── noah-inkscape/
│           ├── init.lua
│           ├── label.lua
│           └── telescope.lua
├── palettes/
│   ├── AU-colors.gpl
│   └── noah-technical.gpl
├── scripts/
│   ├── export_figure
│   ├── new_figure
│   ├── open_figure
│   ├── preview_svg
│   ├── render_thumbnail
│   ├── strip_export_layers.py
│   └── watch_figure
├── styles/
│   ├── stroke_calibration.svg
│   └── style_master.svg
├── symbols/
└── templates/
    └── noah-technical-full.svg
```

The Neovim and Hammerspoon modules derive the repository root from their real
file path, so they can be symlinked into the normal configuration directories
without losing access to `scripts/`, `templates/`, or `symbols/`.

---

# Requirements

## Core

- macOS
- Inkscape
- Neovim **0.10+**
- a TeX distribution with LuaLaTeX/latexmk as needed by the surrounding project
- VimTeX
- Telescope.nvim
- plenary.nvim (Telescope dependency)
- `fswatch`
- Python 3

## For visual Telescope previews

- `chafa`

Without `chafa`, the picker still works; the preview window explains how to
install it instead of failing the picker.

## For Hammerspoon automation

- Hammerspoon
- Accessibility permission for Hammerspoon

Hammerspoon supplies:

- watcher lifecycle cleanup;
- semantic style mode;
- symbol picker;
- Inkscape ↔ Neovim LaTeX label editing.

## For the LaTeX popup

- iTerm2
- LuaSnip is optional, but is loaded when available

---

# Installation

## 1. Download the repository

### Git / HTTPS

```sh
git clone https://github.com/B1gum/noah-inkscape.git ~/code/noah-inkscape
cd ~/code/noah-inkscape
```

### Git / SSH

If GitHub SSH is already configured:

```sh
git clone git@github.com:B1gum/noah-inkscape.git ~/code/noah-inkscape
cd ~/code/noah-inkscape
```

### GitHub ZIP

You can also use **Code → Download ZIP** on GitHub, extract it somewhere
permanent, and use that extracted directory as the repository root.

Do not put the repository in a temporary Downloads extraction location if you
are going to symlink configuration files to it.

For the commands below, replace:

```text
~/code/noah-inkscape
```

with the actual repository path if you use another location.

---

## 2. Install runtime dependencies

If you use Homebrew:

```sh
brew install fswatch chafa python
```

Install the GUI applications if needed:

```sh
brew install --cask inkscape hammerspoon iterm2
```

Install Neovim separately if it is not already present:

```sh
brew install neovim
```

The scripts look for Inkscape in this order:

1. an `inkscape` executable on `$PATH`;
2. `/Applications/Inkscape.app/Contents/MacOS/inkscape`.

Verify the important command-line dependencies:

```sh
command -v fswatch
command -v chafa
command -v python3
command -v nvim
```

---

## 3. Make the scripts executable

Git normally preserves the executable bits. If needed:

```sh
cd ~/code/noah-inkscape
chmod +x scripts/*
```

---

## 4. Install the Neovim module

The simplest setup is to symlink the module into the normal Lua path:

```sh
mkdir -p ~/.config/nvim/lua
ln -sfn \
  ~/code/noah-inkscape/nvim/lua/noah-inkscape \
  ~/.config/nvim/lua/noah-inkscape
```

Then load it from your Neovim configuration:

```lua
require("noah-inkscape").setup()
```

A convenient mapping could be:

```lua
vim.keymap.set("n", "<leader>f", "<cmd>Figure<CR>", {
    desc = "Open or create Inkscape figure",
})
```

The module expects Telescope to be available. A normal plugin-manager setup
should therefore include at least:

```lua
{
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
}
```

The figure workflow also deliberately relies on VimTeX for the active project
root:

```lua
vim.b.vimtex.root
```

Therefore run `:Figure` from a buffer that belongs to an initialized VimTeX
project.

### Expected LaTeX project layout

```text
course/
├── main.tex
├── chapters/
└── figures/
    ├── beam_fbd.svg
    ├── beam_fbd.pdf
    └── beam_fbd.pdf_tex
```

`figures/` is created automatically if it does not exist.

---

## 5. Install the Hammerspoon modules

Create symlinks for the four modules:

```sh
mkdir -p ~/.hammerspoon

ln -sf ~/code/noah-inkscape/hammerspoon/inkscape_styles.lua \
  ~/.hammerspoon/inkscape_styles.lua

ln -sf ~/code/noah-inkscape/hammerspoon/inkscape_symbols.lua \
  ~/.hammerspoon/inkscape_symbols.lua

ln -sf ~/code/noah-inkscape/hammerspoon/inkscape_latex.lua \
  ~/.hammerspoon/inkscape_latex.lua

ln -sf ~/code/noah-inkscape/hammerspoon/inkscape_watchers.lua \
  ~/.hammerspoon/inkscape_watchers.lua
```

Add this to `~/.hammerspoon/init.lua`:

```lua
require("inkscape_watchers").start()
require("inkscape_styles").start()
require("inkscape_latex").start()
```

`inkscape_styles.start()` also attempts to start the watcher manager as a
safety net. Starting it explicitly as above is still recommended; startup is
idempotent.

Reload Hammerspoon after making changes:

```text
Hammerspoon menu bar icon → Reload Config
```

### Permissions

On first use, macOS should ask for Accessibility access. If necessary, open:

```text
System Settings
→ Privacy & Security
→ Accessibility
→ Hammerspoon
```

and enable it.

This is required for keyboard interception and reliable menu actions inside
Inkscape.

---

## 6. Configure the iTerm2 LaTeX popup profile

This setup matters only for the **Shift+T** Inkscape label editor.

The Hammerspoon module does **not** create an ordinary iTerm window and does not
select a profile by name. Instead it programmatically presses the hotkey of a
**dedicated iTerm2 hotkey window**.

The exact hotkey currently expected by `hammerspoon/inkscape_latex.lua` is:

> This is an **internal transport shortcut**, not part of the human-facing Hammerspoon Hyper layer (`⌘⇧`). It intentionally stays on the old full-modifier chord so it cannot collide with mnemonic course shortcuts such as `⌘⇧L`.

```text
Control + Option + Shift + Command + L
```

You normally never press this chord yourself. In normal use you press
**Shift+T in Inkscape**, and Hammerspoon invokes the iTerm hotkey for you.

### Create the profile

1. Open **iTerm2 → Settings → Keys**.
2. Click **Create a Dedicated Hotkey Window**.
3. Let iTerm2 create the associated hotkey profile.
4. Rename the profile to **Inkscape LaTeX** for clarity.
5. Set its hotkey to:

   ```text
   Control + Option + Shift + Command + L
   ```

### Dedicated hotkey-window settings

In the hotkey-window configuration:

- **Floating window:** ON
- **Animate showing and hiding:** optional; OFF feels fastest
- **Pin hotkey window:** not required

The important full-screen behavior is **Floating window**.

### Profile window settings

Open the **Inkscape LaTeX** profile and go to its **Window** settings.

Set:

```text
Space: All Spaces
```

`Floating window + All Spaces` is important because it allows the dedicated
terminal to appear on top of Inkscape even when Inkscape is in a macOS
full-screen Space.

### Profile command

Leave the profile using its normal shell / login shell. Do **not** configure a
custom startup command that launches Neovim.

Hammerspoon creates a temporary runner and types that runner into the hotkey
window when needed.

Conceptually the popup starts:

```sh
nvim /tmp/...tex \
  -c "lua require('noah-inkscape.label').setup()"
```

The Hammerspoon module then:

- waits for the dedicated window to appear;
- moves it to the display containing the active Inkscape window;
- resizes it to a compact popup;
- sends the temporary Neovim command;
- closes the transient terminal when editing is finished;
- restores focus to Inkscape.

Current popup size limits are approximately:

```text
width:  58% of the usable display, clamped to 560–780 px
height: 24% of the usable display, clamped to 220–300 px
```

So the iTerm profile itself does not need carefully tuned dimensions.

### If you change the dedicated hotkey

Update this block in `hammerspoon/inkscape_latex.lua` as well:

```lua
iterm_hotkey = {
    mods = { "ctrl", "alt", "shift", "cmd" },
    key = "l",
},
```

Then reload Hammerspoon.

---

## 7. Install the Inkscape palettes

The repository contains:

```text
palettes/AU-colors.gpl
palettes/noah-technical.gpl
```

The safest installation method is to let Inkscape open the correct user
resource folder for your installed version:

1. Open **Inkscape → Preferences → System**.
2. Use **Open – Color Palettes**.
3. Copy the `.gpl` files from this repository into the opened folder.
4. Restart Inkscape.

This avoids relying on a hard-coded macOS configuration path that may differ
between Inkscape packaging/version choices.

`Noah Technical` contains the semantic technical palette used by this setup.

---

# Neovim workflow

## `:Figure`

Main figure command.

From a VimTeX project:

```vim
:Figure
```

Telescope displays existing SVGs below `figures/` plus:

```text
+ New figure…
```

### Existing figure

Select an existing SVG and press **Enter**:

```text
Telescope
→ scripts/open_figure
→ Inkscape
→ scripts/watch_figure
→ automatic exports on save
```

### Create a figure from the picker

Select `+ New figure…` and press **Enter**, then enter a name.

Alternatively type the desired name into the main Telescope prompt and press:

```text
Ctrl-A
```

The workflow then opens the template picker.

## `:FigureNew`

```vim
:FigureNew
```

prompts for:

1. figure name;
2. template;
3. optional caption.

You can supply the name directly:

```vim
:FigureNew beam_fbd
```

which skips the name prompt and goes directly to template selection.

### Figure names

The shell creation script accepts names matching:

```text
^[a-z0-9][a-z0-9_-]*$
```

Examples:

```text
beam_fbd
stress_element
shaft-geometry
```

The `.svg` suffix is added automatically.

---

# Automatic export and watcher lifecycle

## What starts a watcher?

Figures opened through `scripts/open_figure` start `scripts/watch_figure` in the
background.

`new_figure` also uses `open_figure`, so newly created figures get the same
watcher behavior automatically.

## One watcher per SVG

`watch_figure` hashes the canonical SVG path and stores state below:

```text
$TMPDIR/noah-inkscape/
```

If a live watcher already exists for the exact same SVG, opening that figure
again does not start a duplicate watcher.

## Save behavior

On startup:

```text
watch_figure
→ export_figure immediately
```

Afterward:

```text
SVG save
→ fswatch event
→ export_figure
→ .pdf + .pdf_tex refreshed
```

`fswatch` uses a short latency so bursts of filesystem activity around one save
are coalesced rather than causing a long export queue.

## Close behavior

`hammerspoon/inkscape_watchers.lua` monitors Inkscape document windows.

For each registered watcher it looks for an Inkscape window title containing
the SVG filename (or filename without `.svg`).

The lifecycle is:

```text
open_figure
→ Inkscape document opens
→ watcher writes PID + SVG path
→ Hammerspoon sees matching window
→ watcher is marked as "seen"
→ document window closes
→ matching window disappears
→ Hammerspoon sends TERM to watcher shell
→ watcher kills its fswatch child
→ watcher state is removed
```

There is a short startup grace period so a watcher is not killed merely because
Inkscape has not finished creating its document window yet.

### Important

Automatic close cleanup requires Hammerspoon to be running with
`inkscape_watchers` loaded.

The save watcher itself can run without Hammerspoon, but there is then no
application-window lifecycle signal telling it that the figure was closed.

---

# Non-exporting guide layer

The working SVG can contain guides/construction objects that should remain
visible while drawing but should never appear in the generated PDF.

`export_figure` solves that without mutating the source.

## Export pipeline

```text
figure.svg
  ↓ copy beside source
.figure.export.XXXXXX.svg
  ↓ strip_export_layers.py
remove matching guide layer(s)
  ↓ Inkscape CLI
figure.pdf + figure.pdf_tex
  ↓
delete temporary SVG
```

The temporary file is created beside the source so relative linked-image paths
continue to resolve normally during export.

## Default excluded layer

```text
10 - GUIDES
```

Layer-name comparison:

- ignores case;
- treats `-`, `–`, `—`, `−`, and related dash forms equivalently;
- normalizes spacing around the dash.

Therefore all of these match the default:

```text
10 - GUIDES
10 - Guides
10 – Guides
10 — guides
```

## Change the excluded layer name

For a one-off shell session:

```sh
export NOAH_INKSCAPE_GUIDES_LAYER="99 - WORKING"
```

Then run/open figures normally.

If you want to exclude more than one layer permanently, extend the
`strip_export_layers.py` invocation in `scripts/export_figure` with additional:

```text
--exclude-layer "..."
```

arguments.

---

# Visual previews

## Figure and template previews

Telescope uses:

```text
nvim/lua/noah-inkscape/telescope.lua
→ scripts/preview_svg
→ scripts/render_thumbnail
→ Inkscape CLI renders PNG
→ chafa renders PNG in Telescope terminal preview
```

Thumbnails are cached under:

```text
$TMPDIR/noah-inkscape/thumbnails/
```

The cache key is based on the full SVG path. A thumbnail is regenerated when
the SVG is newer than the cached PNG.

`render_thumbnail` normally uses drawing bounds. If an SVG has no drawable
content (for example a deliberately blank template), it falls back to the SVG
page so the preview still has something meaningful to display.

## Symbol previews

The symbol picker uses **two preview levels**:

1. a compact image inside each normal `hs.chooser` row;
2. a large live preview panel beside the chooser for the currently highlighted
   symbol.

The row icons are intentionally rendered through `scripts/render_thumbnail`
instead of loading the SVG page directly. The renderer crops to the symbol's
actual drawing bounds, adds a small margin, and places the technical black
strokes on a light background. This makes the limited-size chooser icon much
more useful.

The large preview panel follows the currently selected row (keyboard or mouse)
and displays the same tightly-cropped render at several hundred pixels. It is
implemented with `hs.canvas` because `hs.chooser` itself does not expose a row
height/image-well size control.

Symbol preview PNGs live under:

```text
$TMPDIR/noah-inkscape/symbol-thumbnails-v2/
```

They are regenerated when the source SVG changes. The `v2` cache path is
intentional so older uncropped thumbnails cannot survive this upgrade.

---

# Inkscape style mode

Style mode is implemented in:

```text
hammerspoon/inkscape_styles.lua
```

It is intentionally **OFF by default**.

## Toggle

```text
'     toggle style mode
```

When style mode is OFF, ordinary letter/punctuation typing passes through to
Inkscape normally.

When style mode is ON, the following bare keys become semantic style commands.

## Stroke width

| Key | Meaning | Width |
|---|---|---:|
| `s` | standard | 0.35 mm |
| `e` | emphasized | 0.55 mm |
| `h` | heavy | 0.85 mm |

## Dash pattern

| Key | Meaning |
|---|---|
| `l` | solid / no dash |
| `.` | dotted |
| `:` | light-dashed |
| `;` | dashed |

## Arrow marker

| Key | Meaning |
|---|---|
| `n` | no arrow / remove arrow marker |
| `a` | axes arrow |
| `f` | force arrow |

## Symbols

The symbol picker is independent of style mode:

```text
Shift+S    open symbol picker from anywhere in Inkscape
```

Bare `s` retains its normal Inkscape meaning outside style mode. `Shift+S` works with style mode both ON and OFF.

## Why the commands compose

Each style key writes an Inkscape clipboard style containing only the property
family that key owns.

For example:

```text
h
```

changes stroke width, but does not intentionally reset dash pattern or marker.

Therefore:

```text
h → : → x
```

builds a heavy + light-dashed + force-arrow combination.

## Text entry

Because style mode uses bare keys, leave it before typing ordinary Inkscape
text:

```text
'    style mode OFF
```

---

# Engineering symbol library

Symbols live in:

```text
symbols/
```

Subdirectories become categories automatically.

Example:

```text
symbols/
├── _sources/                # symbol workspaces made from the symbol sheet
├── dynamics/
│   ├── damper.svg
│   └── spring.svg
└── supports/
    ├── fixed_support.svg
    ├── pinned_support.svg
    └── roller_support.svg
```

Files under directories beginning with `_` are ignored by the picker, so you can
keep drawing/workbench sources there without polluting the insertable library.

## Open the picker

In Inkscape:

```text
Shift+S    symbol picker
```

This shortcut is always available while Inkscape is frontmost; style mode does
not need to be enabled.

The chooser supports fuzzy subsequence matching, so abbreviated searches can
match longer symbol names/categories.

## Picker actions

For a saved symbol:

```text
Enter          insert the clean library symbol into the current drawing
Shift+Enter    open that symbol's editable source sheet
```

`Shift+Enter` looks for the corresponding file under `symbols/_sources/`. For
older symbols without a source sheet it safely opens the clean library SVG
itself, which is still editable vector content.

As you move through the chooser with the arrow keys or mouse, a large preview
panel follows the highlighted symbol. The tiny icon in the row remains only a
compact cue; the side panel is the primary visual preview.

Normal Enter places the SVG on Inkscape's native SVG clipboard and invokes
Paste. The inserted result remains ordinary editable vector content rather than
a raster screenshot.

## Create a new symbol from the current selection

1. Select the desired objects in Inkscape.
2. Open the symbol picker.
3. Either:

   ```text
   + New symbol sheet…
   ```

   to create a dedicated drawing sheet at:

   ```text
   symbols/_sources/<category>/<name>.svg
   ```

   or:

   ```text
   + New symbol from selection…
   ```

4. Enter a name, optionally with a category:

   ```text
   dynamics/spring
   ```

Allowed name components contain lowercase letters, numbers, `_` and `-`.

The module copies the current Inkscape selection and writes its native SVG
clipboard representation to the new `.svg` file.

### Recommended workflow

1. Create a new symbol sheet.
2. Draw the symbol on the `30 - Symbol` layer.
3. Keep the actual symbol mostly inside the **72 × 72 mm** inner box.
4. Only exceed that when genuinely necessary, and treat the **120 × 120 mm**
   outer box as the hard upper bound for a normal reusable symbol.
5. Select the finished symbol geometry.
6. Save it with **New symbol from selection…** into its final category.

The next time the chooser is opened, the saved symbol is discovered
automatically.

The bundled symbol set and the symbol-sheet template are intentionally scaled up to approximately **600%** of the earlier size so inserted symbols are much easier to see and use without immediate resizing.

## Bundled symbol set

The repository now ships with **17 calibrated mechanics symbols**. Every symbol
has a clean insertable SVG under `symbols/` and a corresponding editable source
sheet under `symbols/_sources/`.

| Category | Symbol | File | Default orientation / reference |
|---|---|---|---|
| Supports | Fixed support | `supports/fixed_support.svg` | vertical wall; attachment at wall centre |
| Supports | Pinned support | `supports/pinned_support.svg` | ground below; attachment at pin/apex |
| Supports | Roller support | `supports/roller_support.svg` | ground below; attachment at pin/apex |
| Supports | Pillow-block bearing | `supports/pillow_block_bearing.svg` | mounting base below; reference at shaft centre |
| Dynamics | Spring | `dynamics/spring.svg` | horizontal; endpoints are attachments |
| Dynamics | Damper | `dynamics/damper.svg` | horizontal; endpoints are attachments |
| Dynamics | Mass block | `dynamics/mass_block.svg` | generic translational mass; side-centre attachment points |
| Dynamics | Wheel on ground | `dynamics/wheel_ground.svg` | ground below; reference at hub centre |
| Dynamics | Torsional spring | `dynamics/torsional_spring.svg` | reference at spring centre; outer lead is connection |
| Dynamics | Rotational damper | `dynamics/rotational_damper.svg` | reference at shaft centre |
| Joints | Revolute joint | `joints/revolute_joint.svg` | pin centre is the joint reference |
| Joints | Prismatic joint | `joints/prismatic_joint.svg` | default translation axis horizontal |
| Mechanisms | Pulley | `mechanisms/pulley.svg` | hub centre is reference |
| Mechanisms | Gear pair | `mechanisms/gear_pair.svg` | generic external meshing gears |
| Actuators | Hydraulic cylinder | `actuators/hydraulic_cylinder.svg` | horizontal; eye centres are attachments |
| Coordinates | 2D coordinate system | `coordinates/axes_2d.svg` | +x right, +y up |
| Coordinates | 3D coordinate system | `coordinates/axes_3d.svg` | compact oblique +x/+y/+z system |

The set uses the normal **0.35 mm** technical stroke for primary geometry and a
lighter **0.25 mm** stroke for secondary details. Symbols stay inside the
72 × 72 mm nominal region wherever practical; only components whose geometry
benefits from a little more length use some of the surrounding 120 × 120 mm
working envelope.

The support symbols intentionally contain only the reusable support graphic —
not a beam/member — so they can be rotated or mirrored and attached to your own
geometry. Springs, dampers, joints and actuators similarly include only the
connection geometry needed to make placement fast without forcing a particular
mechanism layout.

---

# LaTeX label popup

Implemented by:

```text
hammerspoon/inkscape_latex.lua
nvim/lua/noah-inkscape/label.lua
```

## Open

In Inkscape:

```text
Shift+T
```

Lowercase `t` is not replaced, so the normal Inkscape text-tool shortcut
remains usable.

## New label

With no suitable text object selected, Shift+T opens a one-line Neovim editor
initialized as a math label.

Type/edit using the normal TeX environment and press:

```text
Enter      accept/save
Ctrl-C     cancel
```

`Alt-Enter`, `Ctrl-Enter`, and normal Vim `ZZ` remain fallback exits.

## Edit an existing label

If the current Inkscape selection copies as exactly one simple text object, the
module extracts its text, opens it in the same popup, and pastes the edited SVG
back **in place**.

It deliberately refuses to pretend that complicated SVG text structures are a
single raw label.

## One-line design

The popup is specifically for ordinary labels such as:

```tex
$F_x$
$\omega$
$\sigma_{xx}$
$T_1$
```

Multi-line equations or layout-sensitive structures should be handled by a
more appropriate rendered-LaTeX workflow such as TexText rather than forcing
them through this lightweight label editor.

## Inkscape appearance versus final appearance

For a newly created raw label, Hammerspoon creates an approximate Inkscape text
object using:

```text
Latin Modern Roman
~10 pt visual size
```

This is only a layout aid. PDF+LaTeX export is what gives the final document its
real LaTeX typography.

---

# Templates

Templates live in:

```text
templates/**/*.svg
```

The current main template is:

```text
templates/noah-technical-full.svg
```

Any additional `.svg` placed under `templates/` is automatically discovered by
the Neovim template picker. Subdirectories are supported.

The current technical template includes named working layers including:

```text
30 - LaTeX
20 – Construction
10 – Guides
00 - Background
```

The `10 – Guides` layer is kept in the editable SVG and removed automatically
from export copies.

To add a template, simply add another SVG to `templates/`. There is no picker
configuration table to update.

---

# Palettes

## Noah Technical

`palettes/noah-technical.gpl` currently contains:

| Semantic color | RGB |
|---|---|
| Text | 0, 0, 0 |
| White | 255, 255, 255 |
| Primary geometry | 0, 37, 70 |
| Secondary geometry | 0, 61, 115 |
| Construction | 135, 135, 135 |
| Primary fill | 230, 236, 241 |
| Highlight accent | 250, 187, 0 |
| Highlight fill | 254, 241, 204 |
| Warning | 226, 0, 26 |
| Positive | 139, 173, 63 |
| Secondary accent | 101, 90, 159 |

The intent is semantic use rather than decorative color variety.

`AU-colors.gpl` contains the broader AU-derived palette.

---

# LaTeX integration

## Generated figure block

After a new figure is created successfully, the Neovim module inserts a block
at the location where `FigureNew` was invoked.

With a caption, the generated structure is currently:

```tex
\begin{figure}[ht]
    \centering
    \incfig[1]{beam_fbd}[Example caption]
    \label{fig:beam-fbd}
\end{figure}
```

Without a caption:

```tex
\begin{figure}[ht]
    \centering
    \incfig[1]{beam_fbd}
\end{figure}
```

The figure label converts underscores to hyphens:

```text
beam_fbd → fig:beam-fbd
```

## `\incfig` requirement

This repository does **not** define the LaTeX `\incfig` macro. The surrounding
LaTeX class/package must provide the compatible macro used by your documents.

The workflow assumes that `\incfig` ultimately inputs the generated
`figures/<name>.pdf_tex` and applies the requested relative width.

If your class uses a different figure macro or argument convention, edit
`figure_lines()` in:

```text
nvim/lua/noah-inkscape/init.lua
```

The rest of the SVG creation/export workflow is independent of that formatting
choice.

---

# Standalone scripts

All scripts live under `scripts/` and can be used independently of Neovim.

## Create

```sh
scripts/new_figure beam_fbd /path/to/project/figures
```

Optional explicit template:

```sh
scripts/new_figure \
  beam_fbd \
  /path/to/project/figures \
  /path/to/noah-inkscape/templates/noah-technical-full.svg
```

## Open + watch

```sh
scripts/open_figure /path/to/project/figures/beam_fbd.svg
```

## Watch only

```sh
scripts/watch_figure /path/to/project/figures/beam_fbd.svg
```

## Export once

```sh
scripts/export_figure /path/to/project/figures/beam_fbd.svg
```

Creates:

```text
beam_fbd.pdf
beam_fbd.pdf_tex
```

## Render a PNG thumbnail

```sh
scripts/render_thumbnail input.svg output.png 640
```

## Preview an SVG in a terminal

```sh
scripts/preview_svg input.svg
```

Requires `chafa`.

## Strip working layers manually

```sh
scripts/strip_export_layers.py \
  input.svg \
  cleaned.svg \
  --exclude-layer "10 - GUIDES"
```

Multiple `--exclude-layer` arguments are accepted.

---

# Temporary files and caches

The workflow does not place thumbnail caches or watcher metadata inside your
LaTeX project.

It uses:

```text
$TMPDIR/noah-inkscape/
```

Typical contents:

```text
<hash>.pid       watcher shell PID
<hash>.path      canonical SVG path
<hash>.seen      marker that Inkscape window was observed
<hash>.events    fswatch event stream/count file
<hash>.log       export/watcher log
thumbnails/      Telescope preview PNGs
symbol-thumbnails/ Hammerspoon symbol preview PNGs
```

Normal watcher shutdown removes its PID/path/seen/event files. Logs and cached
thumbnails can remain and be reused/inspected.

It is safe to delete the entire cache/state directory when no figures are being
watched:

```sh
rm -rf "${TMPDIR:-/tmp}/noah-inkscape"
```

---

# Troubleshooting

## `:Figure` says the buffer is not part of a VimTeX project

The module intentionally uses `vim.b.vimtex.root` rather than guessing a root
from the current working directory.

Check:

```vim
:lua print(vim.inspect(vim.b.vimtex))
```

Open/run the command from a TeX buffer where VimTeX has initialized the project.

---

## `open_figure is not executable`

Run:

```sh
chmod +x ~/code/noah-inkscape/scripts/*
```

---

## No Telescope image preview

Check:

```sh
command -v chafa
command -v inkscape
```

If `chafa` is absent:

```sh
brew install chafa
```

If the GUI Inkscape app is installed but `inkscape` is not on `$PATH`, that is
fine as long as this exists:

```text
/Applications/Inkscape.app/Contents/MacOS/inkscape
```

The preview renderer checks that path automatically.

---

## A symbol row has no thumbnail

The chooser first tries native macOS SVG decoding, then falls back to an
Inkscape-rendered PNG.

Verify that:

```text
scripts/render_thumbnail
```

is executable and that the symbol itself opens normally in Inkscape.

Delete the cached fallback thumbnails to force regeneration:

```sh
rm -rf "${TMPDIR:-/tmp}/noah-inkscape/symbol-thumbnails"
```

---

## PDF/pdf_tex contains the guide layer

First verify the layer is an actual Inkscape layer (`inkscape:groupmode="layer"`)
and that its label corresponds to:

```text
10 - GUIDES
```

Dash style and case do not matter.

Test the stripper directly:

```sh
scripts/strip_export_layers.py \
  figures/test.svg \
  /tmp/test-without-guides.svg \
  --exclude-layer "10 - GUIDES"
```

The script prints the names of removed layers.

If your working layer has a different semantic name, set:

```sh
export NOAH_INKSCAPE_GUIDES_LAYER="your layer name"
```

---

## Watchers keep running after closing a figure

Automatic lifecycle cleanup requires Hammerspoon and the watcher manager.

Confirm `~/.hammerspoon/init.lua` contains:

```lua
require("inkscape_watchers").start()
```

Reload Hammerspoon, then check its Console for:

```text
[inkscape_watchers] started
```

Inspect current workflow state:

```sh
ls -la "${TMPDIR:-/tmp}/noah-inkscape"
```

A live watcher has a `.pid` and `.path` pair.

To terminate a specific stale watcher manually:

```sh
kill "$(cat "${TMPDIR:-/tmp}/noah-inkscape/<hash>.pid")"
```

The watcher trap will also terminate its owned `fswatch` child.

---

## The LaTeX popup does not appear

Check the iTerm setup in this order:

1. The profile is a **Dedicated Hotkey Window**, not merely a normal profile.
2. Its hotkey is exactly:

   ```text
   Control + Option + Shift + Command + L
   ```

3. **Floating window** is enabled.
4. Profile **Window → Space** is set to **All Spaces**.
5. `nvim` is available in the shell launched by that profile.
6. Hammerspoon has Accessibility permission.
7. `inkscape_latex` is started from Hammerspoon.

You can test the iTerm half independently by pressing the full-modifier hotkey manually. The dedicated terminal should show/hide even before Hammerspoon is
involved.

---

## Shift+T is swallowed while typing in a dialog/text field

The LaTeX module avoids taking Shift+T when macOS Accessibility reports a
normal text-input UI element. Inkscape's GTK accessibility bridge is not
perfect for every canvas state, so avoid invoking the popup while actively
editing ordinary Inkscape text.

---

## Style keys type letters instead of changing the object

Style mode is OFF by default.

Press:

```text
'
```

and confirm Hammerspoon shows:

```text
Inkscape style mode ON
```

Then select an Inkscape object and use the style key.

---

## Style keys interfere with normal typing

Press:

```text
'
```

again to turn style mode OFF.

The style layer is deliberately explicit rather than trying to infer every
possible GTK text-field state.

---

## Hammerspoon modules cannot be required

Confirm the symlinks:

```sh
ls -l ~/.hammerspoon/inkscape_*.lua
```

and reload Hammerspoon.

The symbol module resolves its symlink back to the repository so it can find
`symbols/` and the thumbnail renderer.

---

# Updating

If installed with Git:

```sh
cd ~/code/noah-inkscape
git pull
```

Because Neovim/Hammerspoon use symlinks, there is normally nothing else to copy
after an update.

Then:

- restart/reload Neovim as needed;
- choose **Reload Config** in Hammerspoon if Hammerspoon Lua changed.

---

# Uninstalling

Remove the Neovim symlink:

```sh
rm ~/.config/nvim/lua/noah-inkscape
```

Remove the Hammerspoon symlinks:

```sh
rm ~/.hammerspoon/inkscape_styles.lua
rm ~/.hammerspoon/inkscape_symbols.lua
rm ~/.hammerspoon/inkscape_latex.lua
rm ~/.hammerspoon/inkscape_watchers.lua
```

Remove the corresponding `require(...).start()` lines from
`~/.hammerspoon/init.lua` and reload Hammerspoon.

Optionally remove cache/state:

```sh
rm -rf "${TMPDIR:-/tmp}/noah-inkscape"
```

Finally delete the repository directory if no longer wanted.

---

# Design principles

This workflow follows a few rules that are worth preserving when extending it:

1. **SVG is the editable source.** PDF/pdf_tex are generated artifacts.
2. **The compiled LaTeX PDF is the final appearance authority.**
3. **Working-only drawing aids should not require manual hide/unhide before every export.**
4. **High-frequency operations deserve shortcuts; rare styles should remain ordinary Inkscape operations.**
5. **Automations should preserve normal Inkscape behavior when their mode is off.**
6. **Figures, templates, and symbols should be visually searchable rather than filename-only whenever practical.**
7. **Background watchers must have a lifecycle and must not accumulate forever.**

