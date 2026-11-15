#!/bin/bash
# LeanKeys unattended update: swaps the app bundle once the running app has quit, then relaunches.
# Usage: swap-update.sh <new .app on the mounted image> <installed .app> <mount point> <dmg> <pid to wait for>
# Whatever happens, including SIGINT/SIGTERM/SIGHUP at logout or shutdown, the EXIT trap puts the old app back if
# it was moved aside and nothing replaced it, detaches the image, deletes the DMG and opens <installed .app>, so
# either the new or the old app comes back. The old app is removed only after the new one is in place.
SRC="$1"
DEST="$2"
MOUNT="$3"
DMG="$4"
PID="$5"

finish() {
    trap - EXIT INT TERM HUP
    [ ! -e "$DEST" ] && [ -e "$DEST.old" ] && mv "$DEST.old" "$DEST"
    hdiutil detach "$MOUNT" -quiet
    rm -f "$DMG"
    open "$DEST"
}
# A signal exits through the EXIT trap, so finish runs exactly once.
trap finish EXIT
trap 'exit 1' INT TERM HUP

while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done

# A previous run that died between the two moves left only .old: put it back before clearing leftovers.
if [ ! -e "$DEST" ] && [ -e "$DEST.old" ]; then mv "$DEST.old" "$DEST"; fi
rm -rf "$DEST.new" "$DEST.old"
if ! cp -R "$SRC" "$DEST.new"; then
    rm -rf "$DEST.new"
    exit 1
fi
if ! mv "$DEST" "$DEST.old"; then
    rm -rf "$DEST.new"
    exit 1
fi
if ! mv "$DEST.new" "$DEST"; then
    rm -rf "$DEST"
    mv "$DEST.old" "$DEST"
    rm -rf "$DEST.new"
    exit 1
fi
rm -rf "$DEST.old"
exit 0
