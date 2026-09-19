#!/usr/bin/env bash
# waybar's notify (do-not-disturb) toggle: the bell is the button, the
# moon next to it (a clone of the menu bar's Focus item, kept visible
# always: com.apple.controlcenter FocusModes = 18) the picture of the
# state. The state itself comes from the DoNotDisturb assertions store,
# readable since sketchybar has Full Disk Access (see the README): the
# bell turns yellow while a Focus is on, like waybar's
# #custom-notify.dnd, and the popup names the mode and since when. A
# click (focus_toggle, raised by the bell and the moon) opens the Focus
# popover and flips the Do Not Disturb checkbox: UI scripting under
# sketchybar's accessibility grant, no synthetic Escape anywhere (it
# would land in the focused app); a Shortcut would need iCloud.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

store="$HOME/Library/DoNotDisturb/DB/Assertions.json"

# "off" or "<mode>, on since HH:MM (<reason>)"
state() {
    jq -r '
        def mode: {"com.apple.donotdisturb.mode.default": "Do Not Disturb",
                   "com.apple.sleep.sleep-mode": "Sleep",
                   "com.apple.focus.reduce-interruptions": "Reduce Interruptions"}[.]
                  // (split(".") | last);
        (.data[0].storeAssertionRecords // []) as $r
        | if ($r | length) == 0 then "off"
          else ($r[0]
                | "\(.assertionDetails.assertionDetailsModeIdentifier | mode), on since "
                  # Apple epoch (2001) to unix
                  + ((.assertionStartDateTimestamp + 978307200) | floor | strflocaltime("%H:%M"))
                  + " (" + (.assertionDetails.assertionDetailsReason // "?")
                  + (if .assertionDetails.assertionDetailsLifetime.assertionDetailsLifetimeType == "schedule"
                     then ", until the schedule ends" else "" end) + ")")
          end' "$store" 2>/dev/null || echo "unknown (no Full Disk Access?)"
}

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        popup_lines "$NAME" "Focus: $(state)"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

# focus_toggle: the same from outside (`sketchybar --trigger focus_toggle`)
if [ "${SENDER:-}" = mouse.clicked ] || [ "${SENDER:-}" = focus_toggle ]; then
    if ! osascript >/dev/null <<'AS'
on findBox(el, depth)
    tell application "System Events"
        try
            if (value of attribute "AXIdentifier" of el) is "focus-mode-activity-com.apple.donotdisturb.mode.default" then return el
        end try
        if depth < 8 then
            repeat with c in (UI elements of el)
                set hit to my findBox(c, depth + 1)
                if hit is not missing value then return hit
            end repeat
        end if
    end tell
    return missing value
end findBox

tell application "System Events" to tell process "ControlCenter"
    set fm to (first menu bar item of menu bar 1 whose value of attribute "AXIdentifier" is "com.apple.menuextra.focusmode")
    click fm
    delay 1
    set w to window 1
end tell
set box to my findBox(w, 0)
tell application "System Events" to tell process "ControlCenter"
    if box is missing value then
        click fm
        error "Do Not Disturb toggle not found"
    end if
    click box
    # the toggle needs a moment before the popover goes away
    delay 1
    click fm
end tell
AS
    then
        open 'x-apple.systempreferences:com.apple.Focus-Settings.extension'
    fi
    sleep 1
fi

if [ "$(state)" = off ]; then
    sketchybar --set "$NAME" icon.color=$MUTED_COLOR
else
    sketchybar --set "$NAME" icon.color=$WARNING_COLOR
fi
