# Tests/find.itest.sh - Find through the real engine (appletbuilder itest, OMC 5.5).
#
# The omctest suites (*.test.sh) run Find's handlers one at a time with stand-in tools; this
# file launches the applet itself and drives its window over the bridge, so the launch chain
# (main command, NEXT_COMMAND_ID find.new, INIT_SUBCOMMAND_ID find.init, then
# find.update.all.controls), the controls' actionIDs and the real omc_dialog_control round
# trip are what is checked.
#
# Every search runs inside $ITEST_WORK. The delete sections check the command first and press
# Find only when it names that folder and a pattern nothing else on the machine matches, so a
# mistake can only ever cost the test's own files.

eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
    "$ITEST_APP/Contents/Resources/Scripts/find.library.sh")"
FIND_BUTTON_ID=11
check "the view ids imported from find.library.sh" "1 3 102 801" \
    "$LOCATION_ID $COMMAND_PREVIEW_ID $PATTERN_ID $ACTION_KIND_ID"

ROOT="$ITEST_WORK/tree"
/bin/mkdir -p "$ROOT/sub"
: > "$ROOT/one.omcitest-del"
: > "$ROOT/sub/two.omcitest-del"
: > "$ROOT/keep.txt"
file_count() { /usr/bin/find "$ROOT" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' '; }

# Sets a field and fires its own action, as typing into it and leaving it does.
edit() { # <window> <view-id> <value>
    itest_set_value "$1" "$2" "$3"
    itest_click "$1" "$2" > /dev/null
    itest_wait_idle
}

section "The launch chain opens a filled-in window"
before="$(itest_windows)"
itest_run Find > /dev/null
itest_wait_idle
window="$(itest_new_window "$before")"
check "the main command opened the Find window" "yes" "$([ -n "$window" ] && printf yes || printf no)"
check "with no recent location it starts in the user's folder" "/Users/$USER" "$(itest_value "$window" "$LOCATION_ID")"
check_contains "find.update.all.controls wrote the command preview" "/usr/bin/find" "$(itest_value "$window" "$COMMAND_PREVIEW_ID")"

section "A folder handed over on the FIND_FOLDER_PATH pasteboard"
itest_set_pasteboard "$ROOT" FIND_FOLDER_PATH
before="$(itest_windows)"
itest_run find.new > /dev/null
itest_wait_idle
window="$(itest_new_window "$before")"
check "a new window opened" "yes" "$([ -n "$window" ] && printf yes || printf no)"
check "it starts in the handed-over folder" "$ROOT" "$(itest_value "$window" "$LOCATION_ID")"
check "and the handoff was used up" "" "$(itest_pasteboard FIND_FOLDER_PATH)"

section "A search prints, remembers its location and deletes nothing"
edit "$window" "$PATTERN_ID" '*.omcitest-del'
expected="/usr/bin/find -x '$ROOT' -iname '*.omcitest-del' -print"
preview="$(itest_value "$window" "$COMMAND_PREVIEW_ID")"
check "the pattern's action updated the preview" "$expected" "$preview"
# Pressed only for the test's own folder: a failed handoff would leave the search on /Users/$USER.
if [ "$preview" = "$expected" ]; then
    check "pressing Find fires find.run" "find.run" "$(itest_click "$window" "$FIND_BUTTON_ID")"
    itest_wait_idle
else
    check "Find was not pressed: the command does not name the test folder" "yes" "no"
fi
check "nothing was deleted" "3" "$(file_count)"
check "no confirmation was asked for" "0" "$(alerts_count)"
check "the location went to the front of the recents" "$ROOT" \
    "$(/usr/bin/head -n 1 "$ITEST_HOME/Library/Application Support/com.abracode.Find/recent_locations" 2>/dev/null)"

section "Delete asks first, and Cancel deletes nothing"
itest_set_value "$window" "$ACTION_KIND_ID" "-delete"
itest_click "$window" "$ACTION_KIND_ID" > /dev/null
itest_wait_idle
# "Also print" (ALSO_PRINT_ID) is on by default, so the delete prints what it removes.
expected="/usr/bin/find -x '$ROOT' -iname '*.omcitest-del' -print -delete"
preview="$(itest_value "$window" "$COMMAND_PREVIEW_ID")"
check "the action's handler updated the preview" "$expected" "$preview"
if [ "$preview" = "$expected" ]; then
    alerts_reset
    alert_answer 1
    itest_click "$window" "$FIND_BUTTON_ID" > /dev/null
    itest_wait_idle
    check "the confirmation was shown" "1" "$(alerts_mention "cannot be undone")"
    check "and Cancel kept every file" "3" "$(file_count)"
else
    check "Find was not pressed: the command does not name the test folder" "yes" "no"
fi

section "Delete with the confirmation accepted"
preview="$(itest_value "$window" "$COMMAND_PREVIEW_ID")"
if [ "$preview" = "$expected" ]; then
    alerts_reset
    alert_answer 0
    itest_click "$window" "$FIND_BUTTON_ID" > /dev/null
    itest_wait_idle
    check "the confirmation was shown again" "1" "$(alerts_count)"
    check "the two matching files are gone, keep.txt stays" "1" "$(file_count)"
    check "keep.txt is the one left" "yes" "$([ -f "$ROOT/keep.txt" ] && printf yes || printf no)"
else
    check "Find was not pressed: the command does not name the test folder" "yes" "no"
fi
