#!/bin/sh
# Tests/20-combo.test.sh - the combo box replacement, and the folder drop.
#
# ActionUI has no editable combo box, so each one is a TextField plus a companion
# Menu acting as its dropdown. The Menu is inserted whole by find.init; each item is
# a Button whose id encodes its combo and its position. find.combo.pick is what makes
# the pair behave like the single control the nib had.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

# Fill the list a given combo builds its dropdown from, the way the applet expects
# to find it. find.init then inserts the menu from it.
seed_combo() { # <field-id> <item> ...
    local field_id="$1"
    shift
    local one_item
    case "$field_id" in
        "$LOCATION_ID")      write_recents recent_locations "$@" ;;
        "$PATTERN_ID")       write_recents recent_patterns "$@" ;;
        "$XATTR_ID")         write_recents recent_extended_attributes "$@" ;;
        "$ACTION_TOOL_ID")   write_recents recent_exec_scripts "$@" ;;
        "$OUTPUT_TARGET_ID") write_recents recent_output_scripts "$@" ;;
        "$CONFIG_ID")
            /bin/mkdir -p "$(configs_dir)"
            /bin/rm -f "$(configs_dir)"/*
            for one_item; do
                printf '%s\t-iname\n' "$PATTERN_KIND_ID" > "$(configs_dir)/$one_item"
            done
            ;;
    esac
}

# The user choosing an item from that combo's dropdown.
pick_item() { # <field-id> <exact item text>
    local field_id="$1"
    local position="$(combo_index_of "$field_id" "$2")"
    if [ -z "$position" ]; then
        printf 'pick_item: %s is not in combo %s\n' "$2" "$field_id" >&2
        return 1
    fi
    omc_trigger "$(combo_item_id "$field_id" "$position")"
    omc_run find.combo.pick
}

section "preconditions"
check "the library names six combo boxes" "6" \
    "$(printf '%s\n' $COMBO_FIELD_IDS | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
# and the window really declares an insertion slot for each of them, so the list
# above cannot drift away from the document it describes.
for _field_id in $COMBO_FIELD_IDS; do
    check "the window declares slot $(combo_picker_id "$_field_id")" "yes" \
        "$(/usr/bin/grep -q "\"id\": $(combo_picker_id "$_field_id")," \
            "$OMCTEST_APP/Contents/Resources/Base.lproj/Find.json" && echo yes || echo no)"
done
check "an item id encodes its combo and position" "110203" \
    "$(combo_item_id "$PATTERN_ID" 3)"

section "picking an item copies it into the field the dropdown belongs to"
reset_window
seed_combo "$PATTERN_ID" '*.swift' '*.json'
omc_run find.init
check "the dropdown was inserted" "2" "$(menu_item_count "$PATTERN_ID")"
pick_item "$PATTERN_ID" '*.swift'
check_status "the handler exited cleanly" 0
check "the pattern field holds the picked item" '*.swift' "$(ui_value "$PATTERN_ID")"

section "a second item from the same dropdown resolves to its own text"
# The positive control for the position arithmetic: if every id mapped to the same
# line, the check above would pass on its own and prove nothing.
pick_item "$PATTERN_ID" '*.json'
check "the second item is not the first" '*.json' "$(ui_value "$PATTERN_ID")"

section "the field's own action runs afterwards, as the nib's combo box did"
reset_window
seed_combo "$PATTERN_ID" '*.swift'
omc_run find.init
chains_reset
pick_item "$PATTERN_ID" '*.swift'
check "the command preview was asked to refresh" "1" "$(chain_asked find.update.output)"
check "and the config was not loaded"            "0" "$(chain_asked find.load.config)"

section "the Config combo is the one that loads instead of refreshing"
# In the nib this combo alone carried commandID find.load.config; every other combo
# carried find.update.output. A single shared handler has to keep that distinction.
reset_window
seed_combo "$CONFIG_ID" "nightly"
omc_run find.init
chains_reset
pick_item "$CONFIG_ID" "nightly"
check "the config name reached the field" "nightly" "$(ui_value "$CONFIG_ID")"
check "and the config was loaded"               "1" "$(chain_asked find.load.config)"
check "rather than only refreshing the preview" "0" "$(chain_asked find.update.output)"

section "every combo box is wired, not just the ones with an obvious dropdown"
reset_window
for _field_id in $COMBO_FIELD_IDS; do
    seed_combo "$_field_id" "picked-$_field_id"
done
omc_run find.init
for _field_id in $COMBO_FIELD_IDS; do
    pick_item "$_field_id" "picked-$_field_id"
    check "combo $_field_id received its item" "picked-$_field_id" "$(ui_value "$_field_id")"
done

section "a view id from no combo at all is refused"
reset_window
handler_log_mark
omc_trigger "$PATTERN_KIND_ID"
omc_run find.combo.pick
check_status "the handler reports the misuse" 1
check "and says which guard rejected it" "1" \
    "$(handler_log_mentions 'not a combo menu item')"
check "and chained nothing" "0" "$(chain_asked find.update.output)"

section "a position with no item behind it is refused rather than blanking the field"
reset_window
seed_combo "$PATTERN_ID" '*.swift'
omc_run find.init
handler_log_mark
omc_trigger "$(combo_item_id "$PATTERN_ID" 40)"
omc_run find.combo.pick
check_status "the handler reports the empty slot" 1
check "and says so" "1" "$(handler_log_mentions 'no item at position')"

section "the chained load really runs, and sees the name the pick just wrote"
# This is the one place the port depends on a handler's write becoming the next
# dispatch's input. The harness records writes but does not feed them forward, so
# the bridge below stands in for what the engine does - and without it, draining
# the chain would prove nothing.
reset_window
seed_combo "$CONFIG_ID" "chained"
write_config "chained" "$SIZE_UNIT_ID	G" "$PATTERN_ID	*.chained"
omc_run find.init
chains_reset
pick_item "$CONFIG_ID" "chained"
check "the load was requested" "1" "$(chain_asked find.load.config)"
omc_control "$CONFIG_ID" "$(ui_value "$CONFIG_ID")"
omc_drain_chain
check "the config's values reached the window" "G" "$(ui_value "$SIZE_UNIT_ID")"
check "all of them"                    "*.chained" "$(ui_value "$PATTERN_ID")"
check "and the refresh ran after it"           "1" "$(chain_asked find.update.all.controls)"

section "a drop on the location field sets the search location"
reset_window
/bin/mkdir -p "$OMCTEST_WORK/dropped-folder"
omc_trigger "$LOCATION_ID"
omc_drop "$OMCTEST_WORK/dropped-folder"
omc_run find.location.dropped
check_status "the drop handler exited cleanly" 0
check "the location is the dropped folder" "$OMCTEST_WORK/dropped-folder" \
    "$(ui_value "$LOCATION_ID")"
check "and the preview was refreshed" "1" "$(chain_asked find.update.output)"

section "dropping a file means the folder holding it"
reset_window
: > "$OMCTEST_WORK/dropped-folder/a-file.txt"
omc_trigger "$LOCATION_ID"
omc_drop "$OMCTEST_WORK/dropped-folder/a-file.txt"
omc_run find.location.dropped
check "the location is the parent folder" "$OMCTEST_WORK/dropped-folder" \
    "$(ui_value "$LOCATION_ID")"

section "a path with a space survives the JSON round trip"
reset_window
/bin/mkdir -p "$OMCTEST_WORK/two words"
omc_trigger "$LOCATION_ID"
omc_drop "$OMCTEST_WORK/two words"
omc_run find.location.dropped
check "the whole path arrived" "$OMCTEST_WORK/two words" "$(ui_value "$LOCATION_ID")"

section "a drop that carries no path is refused rather than clearing the field"
reset_window
omc_control "$LOCATION_ID" "/keep/me"
omc_trigger "$LOCATION_ID" "" '{"items":[],"location":{"x":0,"y":0}}'
omc_run find.location.dropped
check_status "the handler reports the empty drop" 1
check "and the location was not touched" "" "$(ui_value "$LOCATION_ID")"

section "a drop carrying text rather than a path is refused"
# DropHelper offers plain text before the file-URL branch, and only that branch runs
# URL.path - so what arrives is not always a path, and control 1 feeds an eval.
reset_window
omc_control "$LOCATION_ID" "/keep/me"
handler_log_mark
omc_trigger "$LOCATION_ID"
omc_drop "just some dragged text"
omc_run find.location.dropped
check_status "the handler refuses it" 1
check "and says why" "1" "$(handler_log_mentions 'not an absolute path')"
check "the location was not touched" "" "$(ui_value "$LOCATION_ID")"
# Positive control: an absolute path through the very same call is accepted.
reset_window
omc_trigger "$LOCATION_ID"
omc_drop "$OMCTEST_WORK/dropped-folder"
omc_run find.location.dropped
check_status "while a real path still works" 0

section "cumulative: no handler wrote to a view id the window does not declare"
# The menu items are minted at run time, so they are not in the statically extracted
# id set. Declare the ones this file drives rather than switching the check off.
ui_declare_ids $(combo_item_id "$LOCATION_ID" 0) $(combo_item_id "$CONFIG_ID" 0) \
    $(combo_item_id "$PATTERN_ID" 0) $(combo_item_id "$PATTERN_ID" 1) \
    $(combo_item_id "$XATTR_ID" 0) $(combo_item_id "$ACTION_TOOL_ID" 0) \
    $(combo_item_id "$OUTPUT_TARGET_ID" 0)
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

omctest_end
