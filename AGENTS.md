# Working in this repo

## Look at UI changes before calling them done

A change to the bars, a mode indicator, a menu, a notification or a theme
is not verified by reading the diff. Take a picture and look at it, the
way the eye would.

**sway / waybar.** The bar sits at the bottom of the 1920x1080 output:

    grim -g "0,1050 900x30" /tmp/bar.png

waybar rereads its style only on `SIGUSR2` (`swaymsg reload` does not
touch it, it is a separate systemd user unit), so send that first. A
state that only appears in passing can be forced and restored around the
shot:

    swaymsg mode resize && grim -g "0,1050 900x30" shot.png && swaymsg mode default

**macOS / sketchybar.** `screencapture` takes points, not pixels, so the
builtin 3024x1964 screen is 1512x982 and its bottom bar is:

    screencapture -x -R 0,942,1512,40 /tmp/bar.png

Over ssh this returns the wallpaper alone -- windows and bars are missing
unless the calling process has Screen Recording. Run it from a session on
the machine, or read the state with `sketchybar --query <item>` instead,
which needs no permission and reports drawing, colours and popup rows.

**Keystrokes and pointer.** `wtype` types into whatever has focus (a
picker, a dialog, `Escape` to close one) — check that focus first
(`swaymsg -t get_tree | jq '.. | select(.focused? == true) | .app_id'`),
a new window does not always take it and the keys land in the terminal
this session runs in; `swaymsg seat - cursor set X Y`
and `press`/`release button1` move and click the pointer. A drag made of
those does not reach `slurp` — it takes it for a click and snaps to the
window under the pointer.

**Terminal programs.** Render them through a pty rather than guessing:
`python-pyte` replays the escape stream into a screen buffer that can be
printed. Set the window size with `TIOCSWINSZ` first -- a TUI that sees
0x0 exits at once, silently and with status 0.

## Applying

`chezmoi apply`, `swaymsg reload` and `pacman` are the user's to run; do
everything else (data moves, restarts of user services, checks) without
asking. A `run_onchange_` script in `chezmoi status` means its hash
moved and it will run on the next apply, not work left over.
