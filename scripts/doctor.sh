#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0
WARN=0
ok()   { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf 'FAIL %s\n' "$*"; FAIL=$((FAIL+1)); }

printf 'noah-inkscape doctor\nRepository: %s\n\n' "$REPO_ROOT"

for cmd in nvim python3 fswatch; do
    if command -v "$cmd" >/dev/null 2>&1; then ok "$cmd: $(command -v "$cmd")"; else fail "missing command: $cmd"; fi
done
if command -v chafa >/dev/null 2>&1; then ok "chafa: $(command -v chafa)"; else warn "chafa missing; visual terminal previews degrade gracefully"; fi
if command -v inkscape >/dev/null 2>&1 || [ -x /Applications/Inkscape.app/Contents/MacOS/inkscape ]; then ok "Inkscape CLI found"; else fail "Inkscape CLI not found"; fi

for app in Inkscape Hammerspoon iTerm; do
    if [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ]; then ok "$app application found"; else warn "$app application not found"; fi
done

NV="$HOME/.config/nvim/lua/noah-inkscape"
if [ -L "$NV" ]; then
    ok "$NV -> $(readlink "$NV")"
elif [ -e "$NV" ]; then
    warn "$NV exists but is not a symlink; repository may not be the source of truth"
else
    fail "$NV missing; install the Neovim module symlink"
fi

for f in inkscape_styles.lua inkscape_symbols.lua inkscape_latex.lua inkscape_watchers.lua; do
    link="$HOME/.hammerspoon/$f"
    if [ -L "$link" ]; then ok "$link -> $(readlink "$link")"; else fail "$link missing/not symlink"; fi
done

if [ -f "$HOME/.hammerspoon/init.lua" ]; then
    for mod in inkscape_watchers inkscape_styles inkscape_latex; do
        grep -q "require(\"$mod\")" "$HOME/.hammerspoon/init.lua" && ok "Hammerspoon starts $mod" || warn "no explicit $mod require found in ~/.hammerspoon/init.lua"
    done
else
    fail "~/.hammerspoon/init.lua missing"
fi

for script in export_figure new_figure open_figure preview_svg render_thumbnail watch_figure; do
    [ -x "$REPO_ROOT/scripts/$script" ] && ok "scripts/$script executable" || fail "scripts/$script missing/not executable"
done

printf '\nManual checks still required:\n'
printf '  - Hammerspoon Accessibility permission\n'
printf '  - iTerm2 dedicated hotkey window uses Ctrl+Opt+Shift+Cmd+L\n'
printf '  - Inkscape palettes are installed in the active Inkscape user palette directory\n'
printf '  - Shift+T label popup and PDF/pdf_tex export work end-to-end\n'
printf '\nResult: %d failure(s), %d warning(s).\n' "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ]
