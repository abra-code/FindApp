#!/bin/sh
# Tests/60-run.test.sh - pressing Find: the confirmation, and the recents lists.
#
# find.run.sh ends by running the command it built, so every section here points the
# search at a throwaway tree inside $OMCTEST_WORK. That is deliberate: the delete
# path is the one that destroys user data when wrong, and it is the least likely to
# be walked by hand.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

ROOT="$OMCTEST_WORK/tree"

build_tree() {
    /bin/rm -rf "$ROOT"
    /bin/mkdir -p "$ROOT/sub"
    : > "$ROOT/one.log"
    : > "$ROOT/two.log"
    : > "$ROOT/keep.txt"
}

arm_run() { # a window ready to search the fixture tree
    reset_window
    reset_controls_to_app_defaults
    build_tree
    omc_control "$LOCATION_ID" "$ROOT"
    alerts_reset
    alert_answers_reset
    chains_reset
}

section "preconditions"
# Rebuilding a dropdown removes its old items, and a removal targets the item id
# itself - minted at run time, so no document declares it. Named here, before the
# first handler runs, because the check is applied at write time.
declare_combo_item_ids
build_tree
check "the fixture tree was built" "3" \
    "$(/usr/bin/find "$ROOT" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "a plain search runs and leaves the preview showing what it ran"
arm_run
omc_control "$PATTERN_ID" '*.log'
omc_run find.run
check_status "the run exited cleanly" 0
check "the preview shows the command that ran" \
    "/usr/bin/find -x '$ROOT' -iname '*.log' -print" "$(ui_value "$COMMAND_PREVIEW_ID")"
check "nothing was deleted" "3" \
    "$(/usr/bin/find "$ROOT" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "and the user was not asked to confirm anything" "0" "$(alerts_count)"

section "the location and pattern are remembered for next time"
check "the location was added to the recents" "$ROOT" \
    "$(/usr/bin/head -n 1 "$(recents_file recent_locations)")"
check "and the pattern"                       '*.log' \
    "$(/usr/bin/head -n 1 "$(recents_file recent_patterns)")"

section "the most recent entry goes to the front, without duplicating an old one"
arm_run
write_recents recent_patterns '*.old' '*.log'
omc_control "$PATTERN_ID" '*.log'
omc_run find.run
check "the reused pattern moved to the front" '*.log' \
    "$(/usr/bin/head -n 1 "$(recents_file recent_patterns)")"
check "and was not stored twice" "2" \
    "$(/usr/bin/grep -c . "$(recents_file recent_patterns)" | /usr/bin/tr -d ' ')"

section "the exec tool is remembered only when the action actually uses one"
arm_run
omc_control "$ACTION_KIND_ID" -ls
omc_control "$ACTION_TOOL_ID" "/bin/echo {}"
omc_run find.run
check_absent "listing remembers no tool" "$(recents_file recent_exec_scripts)"

arm_run
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" "/bin/echo {}"
omc_control "$ALSO_PRINT_ID" false
omc_run find.run
check "executing remembers the tool" "/bin/echo {}" \
    "$(/usr/bin/head -n 1 "$(recents_file recent_exec_scripts)")"

section "the output target is remembered only when an output kind is chosen"
arm_run
omc_control "$OUTPUT_KIND_ID" "$NO_CHOICE_TAG"
omc_control "$OUTPUT_TARGET_ID" "/usr/bin/wc -l"
omc_run find.run
check_absent "View remembers no target" "$(recents_file recent_output_scripts)"

arm_run
omc_control "$OUTPUT_KIND_ID" "|"
omc_control "$OUTPUT_TARGET_ID" "/usr/bin/wc -l"
omc_run find.run
check "piping remembers the target" "/usr/bin/wc -l" \
    "$(/usr/bin/head -n 1 "$(recents_file recent_output_scripts)")"

section "an extended attribute is remembered only when it is not already offered"
arm_run
omc_control "$XATTR_ID" "com.apple.FinderInfo"
omc_run find.run
check_absent "a shipped attribute is not added to the recents" \
    "$(recents_file recent_extended_attributes)"

arm_run
omc_control "$XATTR_ID" "com.example.mine"
omc_run find.run
check "an attribute of the user's own is remembered" "com.example.mine" \
    "$(/usr/bin/head -n 1 "$(recents_file recent_extended_attributes)")"

arm_run
omc_control "$XATTR_ID" "Ignore"
omc_run find.run
check "and Ignore is not an attribute name" "com.example.mine" \
    "$(/usr/bin/head -n 1 "$(recents_file recent_extended_attributes)")"

section "deleting asks first, and Cancel really does cancel"
arm_run
omc_control "$ACTION_KIND_ID" -delete
omc_control "$PATTERN_ID" '*.log'
alert_answer 1
omc_run find.run
check_status "the run reports it was cancelled" 1
check "the user was asked once" "1" "$(alerts_count)"
check "the alert named the danger" "1" "$(alerts_mention 'cannot be undone')"
check "and every file is still there" "3" \
    "$(/usr/bin/find "$ROOT" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "and confirming it goes through"
# The positive control for the section above: without it, a cancel test passes just
# as well against a build where the delete never worked at all.
arm_run
omc_control "$ACTION_KIND_ID" -delete
omc_control "$PATTERN_ID" '*.log'
omc_control "$ALSO_PRINT_ID" false
alert_answer 0
omc_run find.run
check "the user was still asked" "1" "$(alerts_count)"
check "the matching files are gone" "0" \
    "$(/usr/bin/find "$ROOT" -name '*.log' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "and the others were left alone" "1" \
    "$(/usr/bin/find "$ROOT" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "no other action asks for confirmation"
for _action in -print -print0 -ls; do
    arm_run
    omc_control "$ACTION_KIND_ID" "$_action"
    omc_run find.run
    check "$_action runs without asking" "0" "$(alerts_count)"
done

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

omctest_end
