#!/bin/sh
# Tests/40-config.test.sh - saving and reloading a named set of settings.
#
# A config file is replayed straight back through omc_dialog_control, so it has to
# hold ActionUI's own spellings - "true", and the "none" sentinel - not the "1" and
# "" that find.library.sh normalizes them to for building a command. That is why
# find.save.config.sh deliberately does not source the library.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

section "preconditions"
check "the applet ships a defaults table" "yes" \
    "$([ -s "$APP_RESOURCES/defaults.tsv" ] && echo yes || echo no)"
check "which declares the size unit default" "M" "$(declared_default "$SIZE_UNIT_ID")"
check "and the no-choice sentinel for file type" "$NO_CHOICE_TAG" \
    "$(declared_default "$FILE_TYPE_ID")"

section "saving writes one line per control named in defaults.tsv"
reset_window
reset_controls_to_app_defaults
omc_control "$CONFIG_ID" "nightly"
omc_control "$PATTERN_ID" '*.log'
omc_run find.save.config
check_status "the save exited cleanly" 0
check_exists "the config file was created" "$(configs_dir)/nightly"
check "it has a line per control" \
    "$(/usr/bin/grep -c . "$APP_RESOURCES/defaults.tsv" | /usr/bin/tr -d ' ')" \
    "$(/usr/bin/grep -c . "$(configs_dir)/nightly" | /usr/bin/tr -d ' ')"
check "the edited pattern was recorded" '*.log' "$(config_value nightly "$PATTERN_ID")"

section "and records ActionUI spellings, not the library's normalized ones"
# If find.save.config.sh ever grows a "source find.library.sh" line, normalization
# turns these into "1" and "", ActionUI rejects both on the way back in, and loading
# a config silently stops restoring those controls. These two checks catch that.
check "a checked box is saved as true"  "true" "$(config_value nightly "$ALSO_PRINT_ID")"
check "an unchecked box as false"      "false" "$(config_value nightly "$CASE_SENSITIVE_ID")"
check "and an unmade choice as the sentinel" "$NO_CHOICE_TAG" \
    "$(config_value nightly "$FILE_TYPE_ID")"

section "a config with no name is refused, and the user is told why"
# The message has to reach the user, not just stdout: these handlers are
# exe_script_file with no output window, so an echo goes nowhere anyone can read.
reset_window
reset_controls_to_app_defaults
omc_control "$CONFIG_ID" ""
alerts_reset
handler_log_mark
omc_run find.save.config
check_status "the save reports the missing name" 1
check "the user was shown an alert"     "1" "$(alerts_count)"
check "naming what is missing"          "1" "$(alerts_mention 'Name the config')"
check "and nothing was written to the configs folder itself" "0" \
    "$(handler_log_mentions 'Is a directory')"
check "the configs directory holds only the earlier config" "1" \
    "$(/bin/ls "$(configs_dir)" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "a name with a slash is refused, because it would escape the configs folder"
reset_window
reset_controls_to_app_defaults
omc_control "$CONFIG_ID" "../escaped"
alerts_reset
omc_run find.save.config
check_status "the save reports the bad name" 1
check "and the user was told why" "1" "$(alerts_mention 'cannot contain a slash')"
check_absent "nothing was written above the configs folder" \
    "$(app_support_dir)/escaped"

section "loading applies the defaults first, so a config resets what it omits"
reset_window
# A config that names only the pattern. Everything else must come back to default.
write_config "sparse" "$PATTERN_ID	*.md"
omc_control "$CONFIG_ID" "sparse"
omc_run find.load.config
check_status "the load exited cleanly" 0
check "the named control took the config's value" "*.md" "$(ui_value "$PATTERN_ID")"
check "an unnamed picker came back to its default" "M" "$(ui_value "$SIZE_UNIT_ID")"
check "an unnamed checkbox too"                 "true" "$(ui_value "$ALSO_PRINT_ID")"
check "and the controls were refreshed afterwards" "1" \
    "$(chain_asked find.update.all.controls)"

section "a config naming a control the defaults do not reset still wins"
# Positive control for the section above: proving the override runs after the reset,
# not that the reset simply never happened.
reset_window
write_config "loud" "$PATTERN_ID	*.md" "$SIZE_UNIT_ID	G"
omc_control "$CONFIG_ID" "loud"
omc_run find.load.config
check "the config's size unit overrode the default" "G" "$(ui_value "$SIZE_UNIT_ID")"

section "loading a config that is not there says so instead of half-applying one"
reset_window
omc_control "$CONFIG_ID" "no-such-config"
omc_run find.load.config
check_status "the load reports the missing config" 1
check "the user was told"          "1" "$(alerts_mention 'Could not find the config')"
check "and no refresh was chained" "0" "$(chain_asked find.update.all.controls)"

section "an empty config name is a no-op, not an error the user has to dismiss"
reset_window
omc_control "$CONFIG_ID" ""
omc_run find.load.config
check_status "the load exits quietly" 0

section "loading refuses a slash the same way saving does"
reset_window
alerts_reset
omc_control "$CONFIG_ID" "../../../../etc/passwd"
omc_run find.load.config
check_status "the load reports the bad name" 1
check "and the user was told why" "1" "$(alerts_mention 'cannot contain a slash')"
check "no controls were touched" "" "$(ui_value "$SIZE_UNIT_ID")"

section "a config written before the port still restores its checkboxes"
# The old nib build wrote "1"/"0" for a checkbox and "" for an unmade choice.
# ActionUI accepts neither, and drops the write silently - so without a migration a
# ticked box would come back unticked, which is worse than an error.
reset_window
alerts_reset
write_config "legacy" \
    "$ALSO_PRINT_ID	0" \
    "$CASE_SENSITIVE_ID	1" \
    "$FILE_TYPE_ID	" \
    "$PATTERN_ID	*.c"
omc_control "$CONFIG_ID" "legacy"
omc_run find.load.config
check_status "the load exited cleanly" 0
check "a legacy 1 became a ticked box"    "true" "$(ui_value "$CASE_SENSITIVE_ID")"
check "a legacy 0 became an unticked one" "false" "$(ui_value "$ALSO_PRINT_ID")"
check "and a legacy empty choice became the sentinel" "$NO_CHOICE_TAG" \
    "$(ui_value "$FILE_TYPE_ID")"
check "while a plain text value is untouched" "*.c" "$(ui_value "$PATTERN_ID")"
# The config above names no volume switch, because no config written before this
# option existed can. Load applies defaults.tsv first for exactly this case, so the
# control has to come back on rather than at the Toggle's own false.
check "and a control the config never heard of gets its default" "true" \
    "$(ui_value "$STAY_ON_VOLUME_ID")"
check "the content pattern comes back empty rather than stale" "" \
    "$(ui_value "$CONTENT_ID")"
check "and skipping binaries is on, as the app ships it" "true" \
    "$(ui_value "$CONTENT_SKIP_BINARY_ID")"

section "a saved config reloads into the same command"
# Note this proves the two halves agree, not that either uses ActionUI's spellings:
# the bridge below feeds the recorded values back through the library, which accepts
# the legacy spellings too. The checks on the file itself, further up, are what pin
# the representation.
reset_window
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "/tmp"
omc_control "$CONFIG_ID" "roundtrip"
omc_control "$PATTERN_ID" '*.swift'
omc_control "$CASE_SENSITIVE_ID" true
omc_control "$FILE_TYPE_ID" f
omc_control "$SIZE_COMPARE_ID" +
omc_control "$SIZE_NUMBER_ID" 4
omc_control "$SIZE_UNIT_ID" k
omc_control "$ACTION_KIND_ID" -ls
# The content controls too, and with a pattern carrying a quote and a space: it is
# the one saved value that goes back out through shell_quote into an eval.
omc_control "$CONTENT_ID" "it's a match"
omc_control "$CONTENT_USE_REGEX_ID" true
omc_control "$CONTENT_SKIP_BINARY_ID" false
_expected="$(find_command)"
check "the saved command really carries the content test" "yes" \
    "$(find_has_token /usr/bin/grep)"
check "the command under test is not the trivial one" "yes" \
    "$([ "$_expected" != "/usr/bin/find -x '/tmp' -print" ] && echo yes || echo no)"
omc_run find.save.config
check_status "the save exited cleanly" 0

# Come back to a fresh window, load the config, and bridge what the handler wrote
# back into the environment - the harness records a handler's writes but does not
# feed them to the next dispatch, exactly as a real window would.
reset_window
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "/tmp"
omc_control "$CONFIG_ID" "roundtrip"
omc_run find.load.config
for _line in $(/usr/bin/awk -F'\t' '{ print $1 }' "$(configs_dir)/roundtrip"); do
    omc_control "$_line" "$(ui_value "$_line")"
done
check "the reloaded settings rebuild the same command" "$_expected" "$(find_command)"
check "including the content pattern, quote and all" "it's a match" \
    "$(ui_value "$CONTENT_ID")"
check "and the regex switch it was saved with" "true" "$(ui_value "$CONTENT_USE_REGEX_ID")"
check "and the binary switch turned off"      "false" "$(ui_value "$CONTENT_SKIP_BINARY_ID")"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no bare value write clobbered a table" "" "$(ui_suspect_writes)"
check "the harness detected no misuse" "" "$(ui_errors)"

omctest_end
