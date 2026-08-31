#!/bin/sh
# Tests/30-controls.test.sh - which controls are live, given the current choices.
#
# The nib had no disabled states of its own: every one of these comes from the
# update_*_controls functions calling omc_enable / omc_disable. Each check asserts
# which of those two calls was made, never merely that the control is "not enabled",
# so a handler that skipped the control entirely fails rather than passing quietly.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

# Three states, not two. "untouched" is a real and different answer from "disabled",
# and collapsing them lets a handler that skips the control entirely pass as though
# it had disabled it - which is exactly how the missing id 402 survived the port.
enabled_state() { # <view-id> -> enabled | disabled | untouched
    case "$(ui_enabled "$1")" in
        1) echo enabled ;;
        0) echo disabled ;;
        *) echo untouched ;;
    esac
}

refresh() {
    omc_run find.update.all.controls
}

section "the command preview is rewritten on every refresh"
reset_window
omc_control "$LOCATION_ID" "/tmp"
refresh
check_status "the refresh exited cleanly" 0
check "the preview shows the command" "/usr/bin/find -x '/tmp' -print" \
    "$(ui_value "$COMMAND_PREVIEW_ID")"

section "the regex switch is only meaningful for a full path search"
reset_window
omc_control "$PATTERN_KIND_ID" -iname
refresh
check "searching by name, regex is off limits" "disabled" "$(enabled_state "$USE_REGEX_ID")"
omc_control "$PATTERN_KIND_ID" -ipath
refresh
check "searching by full path, regex is available" "enabled" "$(enabled_state "$USE_REGEX_ID")"

section "the pattern choice handler refreshes the preview and the switch together"
reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_control "$PATTERN_KIND_ID" -ipath
omc_fire find.pattern.choice.change "$PATTERN_KIND_ID" -ipath
check "the preview was rewritten" "/usr/bin/find -x '/tmp' -print" \
    "$(ui_value "$COMMAND_PREVIEW_ID")"
check "and regex became available" "enabled" "$(enabled_state "$USE_REGEX_ID")"

section "the action tool field is live only for the actions that take a tool"
reset_window
for _action in -print -print0 -ls -delete; do
    omc_control "$ACTION_KIND_ID" "$_action"
    refresh
    check "$_action needs no tool" "disabled" "$(enabled_state "$ACTION_TOOL_ID")"
done
for _action in -exec -execdir; do
    omc_control "$ACTION_KIND_ID" "$_action"
    refresh
    check "$_action takes a tool" "enabled" "$(enabled_state "$ACTION_TOOL_ID")"
done

section "Also print is pointless when the action already prints"
reset_window
for _action in -print -print0; do
    omc_control "$ACTION_KIND_ID" "$_action"
    refresh
    check "$_action already prints" "disabled" "$(enabled_state "$ALSO_PRINT_ID")"
done
for _action in -ls -exec -execdir -delete; do
    omc_control "$ACTION_KIND_ID" "$_action"
    refresh
    check "$_action can also print" "enabled" "$(enabled_state "$ALSO_PRINT_ID")"
done

section "the output target is live only once an output kind is chosen"
reset_window
omc_control "$OUTPUT_KIND_ID" "$NO_CHOICE_TAG"
refresh
check "View needs no target" "disabled" "$(enabled_state "$OUTPUT_TARGET_ID")"
for _kind in "|" ">" "?"; do
    omc_control "$OUTPUT_KIND_ID" "$_kind"
    refresh
    check "$_kind takes a target" "enabled" "$(enabled_state "$OUTPUT_TARGET_ID")"
done

section "the size number and unit follow the size comparison"
reset_window
omc_control "$SIZE_COMPARE_ID" "$NO_CHOICE_TAG"
refresh
check "Ignore leaves the number dead" "disabled" "$(enabled_state "$SIZE_NUMBER_ID")"
check "and the unit with it"          "disabled" "$(enabled_state "$SIZE_UNIT_ID")"
omc_control "$SIZE_COMPARE_ID" +
refresh
check "a comparison wakes the number" "enabled" "$(enabled_state "$SIZE_NUMBER_ID")"
check "and the unit"                  "enabled" "$(enabled_state "$SIZE_UNIT_ID")"

section "the permissions grid follows the permissions comparison"
# The grid is one control carrying all nine checkboxes - id 402 in the nib, and the
# one tag that lived in a userDefinedRuntimeAttribute rather than an XML attribute.
# It was missed on the first pass of the ActionUI port, leaving the checkboxes live
# while the picker said Ignore.
reset_window
omc_control "$PERMISSIONS_COMPARE_ID" "$NO_CHOICE_TAG"
refresh
check "Ignore leaves the checkbox grid dead" "disabled" "$(enabled_state "$PERMISSIONS_GRID_ID")"
omc_control "$PERMISSIONS_COMPARE_ID" -
refresh
check "a comparison wakes the grid"         "enabled" "$(enabled_state "$PERMISSIONS_GRID_ID")"

section "each time row's number and unit follow that row's own choice"
reset_window
for _row in 51 52 53 54; do
    omc_control "${_row}1" "$NO_CHOICE_TAG"
done
refresh
for _row in 51 52 53 54; do
    check "row ${_row}1 set to Any leaves its number dead" "disabled" "$(enabled_state "${_row}2")"
    check "and its unit"                                   "disabled" "$(enabled_state "${_row}3")"
done
# One row at a time, to prove the rows are independent rather than moving together.
omc_control "$MTIME_CHOICE_ID" -
refresh
check "waking modification time wakes its number" "enabled" "$(enabled_state "$MTIME_NUMBER_ID")"
check "and its unit"                              "enabled" "$(enabled_state "$MTIME_UNIT_ID")"
check "but not last access's number"               "disabled" "$(enabled_state "$ATIME_NUMBER_ID")"
check "nor creation time's"                        "disabled" "$(enabled_state "$BTIME_NUMBER_ID")"
check "nor last status change's"                   "disabled" "$(enabled_state "$CTIME_NUMBER_ID")"

section "every choice handler updates the controls its own tab owns"
reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_fire find.size.choice.change "$SIZE_COMPARE_ID" +
check "the size handler refreshed the preview" "/usr/bin/find -x '/tmp' -print" \
    "$(ui_value "$COMMAND_PREVIEW_ID")"
check "and enabled the number" "enabled" "$(enabled_state "$SIZE_NUMBER_ID")"

reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_fire find.permissions.choice.change "$PERMISSIONS_COMPARE_ID" -
check "the permissions handler refreshed the preview" "/usr/bin/find -x '/tmp' -print" \
    "$(ui_value "$COMMAND_PREVIEW_ID")"
check "and enabled the grid" "enabled" "$(enabled_state "$PERMISSIONS_GRID_ID")"

reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_fire find.time.choice.change "$ATIME_CHOICE_ID" -
check "the time handler enabled that row" "enabled" "$(enabled_state "$ATIME_NUMBER_ID")"

reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_fire find.action.choice.change "$ACTION_KIND_ID" -exec
check "the action handler enabled the tool field" "enabled" "$(enabled_state "$ACTION_TOOL_ID")"

reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_fire find.output.choice.change "$OUTPUT_KIND_ID" "|"
check "the output handler enabled the target field" "enabled" "$(enabled_state "$OUTPUT_TARGET_ID")"

section "find.update.output only rewrites the preview, it changes no control state"
reset_window
omc_control "$LOCATION_ID" "/tmp"
omc_control "$PATTERN_ID" '*.txt'
omc_fire find.update.output "$PATTERN_ID" '*.txt'
check "the preview picked the pattern up" "/usr/bin/find -x '/tmp' -iname '*.txt' -print" \
    "$(ui_value "$COMMAND_PREVIEW_ID")"
check "and nothing was enabled or disabled" "untouched" "$(enabled_state "$USE_REGEX_ID")"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

omctest_end
