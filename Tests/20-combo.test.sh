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
        "$CONTENT_ID")       write_recents recent_content_patterns "$@" ;;
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
# Before any handler runs: known_ids.txt is consulted at write time, so a declaration
# made at the end of the file would be read after every write it exists to explain.
declare_combo_item_ids
check "the library names seven combo boxes" "7" \
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

section "a search puts its own terms in the dropdown, without reopening the window"
# The recents file was always updated the moment Find was pressed. What was stale was
# the menu, which find.init had built once when the window opened - so the term you
# had just searched for was the one term the dropdown did not offer.
reset_window
reset_controls_to_app_defaults
# Patterns no earlier section used: a list identical to the one the window was last
# built from is left alone on purpose, and starting from one would measure that
# instead of the refresh.
seed_combo "$PATTERN_ID" '*.before'
omc_run find.init
check "the dropdown opens with what was on disk" "1" "$(menu_live_count "$PATTERN_ID")"
/bin/mkdir -p "$OMCTEST_WORK/searched"
omc_control "$LOCATION_ID" "$OMCTEST_WORK/searched"
omc_control "$PATTERN_ID" '*.after'
omc_run find.run
check_status "the search exited cleanly" 0
check "the term just searched for is offered" "yes" "$(menu_lists "$PATTERN_ID" '*.after')"
check "and it is offered first, as the newest" '*.after' \
    "$(menu_live_titles "$PATTERN_ID" | /usr/bin/head -1)"
check "the earlier term is still there" "yes" "$(menu_lists "$PATTERN_ID" '*.before')"
# The ids are positions, so the rebuild reuses them. Without the removal the inserts
# are refused and the menu keeps the old list; with a botched one it shows both.
check "and the menu holds two items, not four" "2" "$(menu_live_count "$PATTERN_ID")"
check "showing exactly what a click resolves through" "yes" \
    "$(menu_matches_snapshot "$PATTERN_ID")"

section "and picking from the refreshed dropdown resolves against the new list"
# The positive control for the section above: the menu addresses items by position,
# so a rebuild that forgot to rewrite the snapshot leaves every id off by one and
# hands back the wrong text - which counting items cannot see.
pick_item "$PATTERN_ID" '*.after'
check "the field holds what was picked" '*.after' "$(ui_value "$PATTERN_ID")"
pick_item "$PATTERN_ID" '*.before'
check "and the other item too" '*.before' "$(ui_value "$PATTERN_ID")"

section "a search that changes nothing leaves the menus alone"
# Every rebuild is a removal followed by an insert, and a removal takes a live item
# id out from under anyone who has that menu open. An unchanged list must not pay it.
reset_window
reset_controls_to_app_defaults
seed_combo "$PATTERN_ID" '*.md'
omc_run find.init
omc_control "$LOCATION_ID" "$OMCTEST_WORK/searched"
omc_control "$PATTERN_ID" '*.md'
omc_run find.run
_inserts="$(ui_calls omc_insert_element)"
_removals="$(ui_calls omc_remove_element)"
omc_run find.run
check "the second search inserted nothing"  "$_inserts"  "$(ui_calls omc_insert_element)"
check "and removed nothing"                 "$_removals" "$(ui_calls omc_remove_element)"
check "while the dropdown still offers the term" "yes" "$(menu_lists "$PATTERN_ID" '*.md')"

section "a rebuild that was interrupted is repaired by the next one"
# The comparison that makes an unchanged list free is also what would make a
# half-inserted dropdown permanent: it matches its own snapshot, so every later
# refresh returns early and the missing items never come back. A handler killed
# mid-rebuild leaves the marker behind, and the marker is what forces the rebuild.
reset_window
reset_controls_to_app_defaults
seed_combo "$PATTERN_ID" '*.crash'
omc_run find.init
check "the dropdown was built once" "1" "$(menu_live_count "$PATTERN_ID")"
check "and nothing is mid-rebuild afterwards" "no" "$(combo_is_rebuilding "$PATTERN_ID")"
: > "$(combo_state_path "$PATTERN_ID").rebuilding"
_inserts="$(ui_calls omc_insert_element)"
omc_control "$LOCATION_ID" "$OMCTEST_WORK/searched"
omc_control "$PATTERN_ID" '*.crash'
omc_run find.run
check "the unchanged list was rebuilt anyway" "yes" \
    "$([ "$(ui_calls omc_insert_element)" -gt "$_inserts" ] && echo yes || echo no)"
check "the dropdown still holds the one term" "1" "$(menu_live_count "$PATTERN_ID")"
check "and the marker was cleared" "no" "$(combo_is_rebuilding "$PATTERN_ID")"

section "a snapshot swept from under an open window does not leave a stale menu"
# The state directory lives in TMPDIR, which the system sweeps out from under a window
# left open for days. Nothing else knows how many item ids are live, and an insert
# whose id is already taken is refused silently - so a refresh that finds no snapshot
# has to assume the worst rather than assume an empty menu.
reset_window
reset_controls_to_app_defaults
seed_combo "$PATTERN_ID" '*.gone'
omc_run find.init
check "the dropdown opens with what was on disk" "1" "$(menu_live_count "$PATTERN_ID")"
/bin/rm -f "$(combo_state_path "$PATTERN_ID")"
_removals="$(ui_calls omc_remove_element)"
omc_control "$LOCATION_ID" "$OMCTEST_WORK/searched"
omc_control "$PATTERN_ID" '*.fresh'
omc_run find.run
check "the ids it could not account for were swept" "yes" \
    "$([ "$(ui_calls omc_remove_element)" -gt "$_removals" ] && echo yes || echo no)"
# By title, not by count: without the sweep the menu holds two items that BOTH read
# "*.gone" - the new inserts are refused and the old list stays - so counting them
# says two and sees nothing wrong.
check "the dropdown holds the two terms" "$(printf '%s\n%s' '*.fresh' '*.gone')" \
    "$(menu_live_titles "$PATTERN_ID")"
check "and shows exactly what a click resolves through" "yes" \
    "$(menu_matches_snapshot "$PATTERN_ID")"

section "a lock left behind by a handler that died is taken, not waited out"
# A rebuild holds a lock so two of them cannot interleave. A handler killed while
# holding it would wedge that dropdown for the life of the window - and it is the
# dropdown most in need of rebuilding, since it was being rebuilt when the handler
# died. The lock names its holder, and a holder that no longer exists loses it.
reset_window
reset_controls_to_app_defaults
seed_combo "$PATTERN_ID" '*.abandoned'
omc_run find.init
# A pid that has really been used and really is gone, rather than one assumed free.
/bin/sh -c 'exit 0' &
_dead_pid=$!
wait "$_dead_pid" 2>/dev/null
/bin/mkdir -p "$(combo_state_path "$PATTERN_ID").lock/owner.$_dead_pid"
omc_control "$LOCATION_ID" "$OMCTEST_WORK/searched"
omc_control "$PATTERN_ID" '*.inherited'
omc_run find.run
check "the refresh went through" "yes" "$(menu_lists "$PATTERN_ID" '*.inherited')"
check "and the menu matches what a click resolves through" "yes" \
    "$(menu_matches_snapshot "$PATTERN_ID")"
check "the lock did not outlive the rebuild" "no" \
    "$([ -d "$(combo_state_path "$PATTERN_ID").lock" ] && echo yes || echo no)"

section "opening a window inserts without sweeping ids nothing has minted yet"
# The sweep above is the expensive branch, and find.init is the one handler entitled
# to skip it: it runs before anything is live, so a missing snapshot there really does
# mean an empty menu. Without that, every window would open by removing 100 ids per
# combo, over the same IPC the inserts go through.
reset_window
reset_controls_to_app_defaults
seed_combo "$PATTERN_ID" '*.opening'
for _field_id in $COMBO_FIELD_IDS; do
    /bin/rm -f "$(combo_state_path "$_field_id")"
done
_removals="$(ui_calls omc_remove_element)"
omc_run find.init
check "the dropdown was built" "1" "$(menu_live_count "$PATTERN_ID")"
check "without a single removal" "$_removals" "$(ui_calls omc_remove_element)"

section "cumulative: no handler wrote to a view id the window does not declare"
# The menu items are minted at run time, so they are not in the statically extracted
# id set - declare_combo_item_ids, at the top of this file, is what names them rather
# than switching the check off.
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

omctest_end
