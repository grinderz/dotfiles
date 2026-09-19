#!/usr/bin/env bash
# same face as the waybar clock: ISO week, weekday, day, month, time; the
# month calendar (waybar's tooltip) in the popup while the mouse is over

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../env.sh
. "$CONFIG_DIR/env.sh"

case "${SENDER:-}" in
    mouse.entered)
        hover_mark "$NAME" entered
        # macOS's cal cannot start the week on Monday: python draws it,
        # ISO week numbers on the left like the clock's W%V, today marked
        mapfile -t lines < <(python3 - <<'PY'
import calendar, datetime
today = datetime.date.today()
cal = calendar.Calendar(firstweekday=0)
print(f"    {today.strftime('%B %Y'):^21}")
print("    Mo Tu We Th Fr Sa Su")
for week in cal.monthdatescalendar(today.year, today.month):
    cells = [f"{d.day:2}" if d.month == today.month else "  " for d in week]
    # the rows are plain labels, one font: the current week gets a mark
    mark = " *" if today in week else "  "
    print(f"W{week[0].isocalendar()[1]:02} " + " ".join(cells) + mark)
PY
)
        popup_lines "$NAME" "${lines[@]}"
        popup_show "$NAME"
        exit 0 ;;
    mouse.exited.global) hover_mark "$NAME" exited; sketchybar --set "$NAME" popup.drawing=off; exit 0 ;;
esac

sketchybar --set "$NAME" label="$(date '+W%V %a %e %b %H:%M')"
