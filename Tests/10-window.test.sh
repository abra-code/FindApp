#!/bin/sh
# Tests/10-window.test.sh - what find.init leaves on screen when the window opens.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

section "preconditions"
_json_name=$(/usr/bin/plutil -extract COMMAND_LIST.1.ACTIONUI_WINDOW.JSON_NAME raw -o - \
    "$OMCTEST_APP/Contents/Resources/Command.plist" 2>/dev/null)
check "the manifest opens an ActionUI window" "Find" "$_json_name"
check "and that document is in the bundle" "yes" \
    "$([ -f "$OMCTEST_APP/Contents/Resources/Base.lproj/$_json_name.json" ] && echo yes || echo no)"
check "defaults.tsv still names ActionUI view variables" "yes" \
    "$(/usr/bin/grep -q 'OMC_ACTIONUI_VIEW_101_VALUE' "$APP_RESOURCES/defaults.tsv" && echo yes || echo no)"
check "the applet still uses the grid and time ids this suite restates" "yes" \
    "$(app_grid_ids_present)"

section "the window opens in its declared state, which is not yet the applet's default"
reset_window
check "the declared defaults loaded" "yes" \
    "$([ "${OMCTEST_DEFAULTS_APPLIED:-0}" -gt 20 ] && echo yes || echo no)"
# An ActionUI Picker has no initial-selection property: it opens on its first option.
# For the size unit that is Bytes, while the applet's documented default is MB. This
# is the gap find.init exists to close, so assert it is really there before asserting
# that init closes it - otherwise the next section proves nothing.
check "the size unit picker opens on the first option" "c" \
    "$OMC_ACTIONUI_VIEW_303_VALUE"
check "and defaults.tsv wants a different one" "M" "$(declared_default "$SIZE_UNIT_ID")"

section "find.init seeds every control from defaults.tsv"
reset_window
omc_run find.init
check_status "init exited cleanly" 0
check "the size unit is the documented default" "M" "$(ui_value "$SIZE_UNIT_ID")"
check "last access is measured in hours"        "h" "$(ui_value "$ATIME_UNIT_ID")"
check "creation time too"                       "h" "$(ui_value "$BTIME_UNIT_ID")"
check "modification time too"                   "h" "$(ui_value "$MTIME_UNIT_ID")"
check "last status change too"                  "h" "$(ui_value "$CTIME_UNIT_ID")"
check "the action starts on Print"         "-print" "$(ui_value "$ACTION_KIND_ID")"
check "Also print starts checked"            "true" "$(ui_value "$ALSO_PRINT_ID")"
check "the file type picker starts on the no-choice sentinel" "$NO_CHOICE_TAG" \
    "$(ui_value "$FILE_TYPE_ID")"
check "the extended attributes field starts at Ignore" "Ignore" "$(ui_value "$XATTR_ID")"
check "init handed off to the control refresh" "1" \
    "$(chain_asked find.update.all.controls)"

section "the search location comes from the dropped object when there is one"
reset_window
omc_object "$OMCTEST_WORK"
omc_run find.init
check "the location is the object" "yes" \
    "$([ "$(ui_value "$LOCATION_ID")" = "$OMCTEST_WORK" ] && echo yes || echo no)"

section "a dropped file means the folder holding it"
reset_window
/bin/mkdir -p "$OMCTEST_WORK/somewhere"
: > "$OMCTEST_WORK/somewhere/a-file.txt"
omc_object "$OMCTEST_WORK/somewhere/a-file.txt"
omc_run find.init
check "the location is the parent folder" "yes" \
    "$([ "$(ui_value "$LOCATION_ID")" = "$OMCTEST_WORK/somewhere" ] && echo yes || echo no)"

section "with no object, the most recent location is offered"
reset_window
write_recents recent_locations "$OMCTEST_WORK/somewhere" "/usr/share"
omc_run find.init
check "the location is the first recent entry" "yes" \
    "$([ "$(ui_value "$LOCATION_ID")" = "$OMCTEST_WORK/somewhere" ] && echo yes || echo no)"

section "each combo box's dropdown is populated as picker options, not list items"
reset_window
write_recents recent_locations "/one" "/two"
write_recents recent_patterns "*.txt" "*.swift"
write_recents recent_exec_scripts "/bin/echo {}"
write_recents recent_output_scripts "/usr/bin/wc -l"
omc_run find.init

check "the location dropdown offers both recents"  "2" "$(menu_item_count "$LOCATION_ID")"
check "and names the first"                      "yes" "$(menu_offers "$LOCATION_ID" "/one")"
check "the pattern dropdown offers both recents"   "2" "$(menu_item_count "$PATTERN_ID")"
check "and names one of them"                    "yes" "$(menu_offers "$PATTERN_ID" '*.swift')"
check "the action tool dropdown offers its recent" "1" "$(menu_item_count "$ACTION_TOOL_ID")"
check "the output dropdown offers its recent"      "1" "$(menu_item_count "$OUTPUT_TARGET_ID")"

check "and what was inserted is valid JSON" "yes" "$(menu_is_valid_json "$LOCATION_ID")"

# The options went to the companion picker, never to the text field itself.
check "the pattern field was left alone" "" "$(ui_prop "$PATTERN_ID" options)"

section "the extended attributes dropdown keeps its shipped list and adds recents"
reset_window
write_recents recent_extended_attributes "com.example.custom"
omc_run find.init
_shipped=$(/usr/bin/grep -c . "$APP_RESOURCES/extended_attributes.txt")
check "the shipped list is not empty" "yes" \
    "$([ "$_shipped" -gt 3 ] && echo yes || echo no)"
check "every shipped attribute plus the recent one is offered" "$(( _shipped + 1 ))" \
    "$(menu_item_count "$XATTR_ID")"
check "including a shipped one"        "yes" "$(menu_offers "$XATTR_ID" 'com.apple.FinderInfo')"
check "and the recent one"             "yes" "$(menu_offers "$XATTR_ID" 'com.example.custom')"

section "a duplicate recent would make two options share a tag, so it is dropped"
reset_window
write_recents recent_patterns "*.txt" "*.txt" "*.md"
omc_run find.init
check "the duplicate was collapsed" "2" "$(menu_item_count "$PATTERN_ID")"

section "an item ending in a bracket does not swallow the next one"
# The dedup sentinel used to be "<item>", so after "a>" it held "<a>>", which
# contains "<a>" - and the next item "a" was silently dropped from the dropdown.
reset_window
write_recents recent_patterns "a>" "a" "b"
omc_run find.init
check "all three are offered" "3" "$(menu_item_count "$PATTERN_ID")"
check "including the one the old sentinel swallowed" "yes" \
    "$(menu_offers "$PATTERN_ID" 'a')"

section "a tab inside a recent item does not destroy the whole dropdown"
# A raw tab is invalid inside a JSON string: NSJSONSerialization rejects the array,
# ActionUI keeps the property as a plain string, and the combo loses every item.
reset_window
write_recents recent_patterns "$(printf 'has\ttab')" "plain"
omc_run find.init
check "the inserted menu is still valid JSON" "yes" "$(menu_is_valid_json "$PATTERN_ID")"
check "and both items survived" "2" "$(menu_item_count "$PATTERN_ID")"

section "the saved configs are listed in the Config dropdown"
reset_window
write_config "nightly" "101	-iname"
write_config "weekly"  "101	-ipath"
omc_run find.init
check "both configs are offered"  "2" "$(menu_item_count "$CONFIG_ID")"
check "and named"               "yes" "$(menu_offers "$CONFIG_ID" "nightly")"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"
check "the id set was extracted" "yes" \
    "$([ -s "$OMCTEST_UI/known_ids.txt" ] && echo yes || echo no)"

omctest_end
