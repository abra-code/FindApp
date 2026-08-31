#!/bin/sh
# Tests/50-library.test.sh - get_command_from_dialog_controls, called directly.
#
# Nothing here dispatches a handler, so there is deliberately no ui_unknown_writes
# trailer: it would pass by construction, which is the definition of a check that
# cannot fail. This file answers one question only - given these control values,
# what find command comes out, and does /usr/bin/find accept it.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

ROOT="$OMCTEST_WORK/tree"

build_tree() {
    /bin/rm -rf "$ROOT"
    /bin/mkdir -p "$ROOT/sub/deeper"
    printf 'hello\n'          > "$ROOT/one.txt"
    printf 'hello world!!!\n' > "$ROOT/TWO.TXT"
    printf 'x\n'              > "$ROOT/sub/three.md"
    : >                         "$ROOT/sub/empty.txt"
    /bin/ln -s "$ROOT/one.txt"  "$ROOT/link.txt"
    /bin/chmod 0644 "$ROOT/one.txt"
    /bin/chmod 0600 "$ROOT/sub/three.md"
}

section "preconditions"
build_tree
check "the fixture tree was built" "yes" "$([ -d "$ROOT/sub/deeper" ] && echo yes || echo no)"
check "and it has a symlink"       "yes" "$([ -L "$ROOT/link.txt" ] && echo yes || echo no)"
check "/usr/bin/find is present"   "yes" "$([ -x /usr/bin/find ] && echo yes || echo no)"

section "an untouched window searches the location and prints"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
check "the whole command" "/usr/bin/find '$ROOT' -print" "$(find_command)"
check "and find accepts it"  "0" "$(find_run_built_command)"
check "and it walks the whole tree" "8" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "alphabetical order is a flag before the location, not after"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ALPHABETICAL_ID" true
check "the -s comes first"   "-s" "$(find_token_at 2)"
check "the location follows" "'$ROOT'" "$(find_token_at 3)"
check "find accepts it"       "0" "$(find_run_built_command)"

section "a Toggle arrives as true/false, where this library was written for 1/0"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ALPHABETICAL_ID" false
check "false really means off" "no" "$(find_has_token -s)"
# The positive control for the check above: the same slot, switched on.
omc_control "$ALPHABETICAL_ID" true
check "and true really means on" "yes" "$(find_has_token -s)"
# The legacy spelling still works, so a config written by the nib build still loads.
omc_control "$ALPHABETICAL_ID" 1
check "the old 1 spelling is still honored" "yes" "$(find_has_token -s)"
omc_control "$ALPHABETICAL_ID" 0
check "and the old 0 spelling too"           "no" "$(find_has_token -s)"

section "the name pattern picks its primary from the kind, case and regex switches"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PATTERN_ID" '*.txt'
check "name, case-insensitive"  "/usr/bin/find '$ROOT' -iname '*.txt' -print" "$(find_command)"
omc_control "$CASE_SENSITIVE_ID" true
check "name, case-sensitive"    "/usr/bin/find '$ROOT' -name '*.txt' -print"  "$(find_command)"
omc_control "$CASE_SENSITIVE_ID" false
omc_control "$PATTERN_KIND_ID" -ipath
check "full path, case-insensitive" "/usr/bin/find '$ROOT' -ipath '*.txt' -print" "$(find_command)"
omc_control "$USE_REGEX_ID" true
check "full path as a regex adds -E" "/usr/bin/find -E '$ROOT' -iregex '*.txt' -print" \
    "$(find_command)"
omc_control "$CASE_SENSITIVE_ID" true
check "and case-sensitive regex"     "/usr/bin/find -E '$ROOT' -regex '*.txt' -print" \
    "$(find_command)"

section "no pattern means no primary at all, not an empty one"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PATTERN_ID" ""
check "no -iname" "no" "$(find_has_token -iname)"
check "no -name"  "no" "$(find_has_token -name)"
# Positive control: the same assertion with a pattern present must find one.
omc_control "$PATTERN_ID" '*.txt'
check "and a pattern does produce one" "yes" "$(find_has_token -iname)"

section "the name search really matches, case and all"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PATTERN_ID" '*.txt'
check "case-insensitive finds both spellings" "4" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
omc_control "$CASE_SENSITIVE_ID" true
check "case-sensitive finds only the lowercase ones" "3" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "the file type picker maps to -type, and its negatives to -not -type"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" f
check "regular files"       "/usr/bin/find '$ROOT' -type f -print" "$(find_command)"
omc_control "$FILE_TYPE_ID" '!d'
check "not directories" "/usr/bin/find '$ROOT' -not -type d -print" "$(find_command)"
check "and find accepts the negated form" "0" "$(find_run_built_command)"
omc_control "$FILE_TYPE_ID" d
check "directories are found"  "3" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "the no-choice sentinel means no clause, not a clause with an empty value"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" "$NO_CHOICE_TAG"
omc_control "$SIZE_COMPARE_ID" "$NO_CHOICE_TAG"
omc_control "$SIZE_NUMBER_ID" 1000
omc_control "$EMPTINESS_ID" "$NO_CHOICE_TAG"
omc_control "$PERMISSIONS_COMPARE_ID" "$NO_CHOICE_TAG"
omc_control "$OUTPUT_KIND_ID" "$NO_CHOICE_TAG"
omc_control "$OUTPUT_TARGET_ID" "/tmp/out.txt"
check "the sentinel adds nothing anywhere" "/usr/bin/find '$ROOT' -print" "$(find_command)"
# Positive controls: each of those pickers does produce a clause when really chosen.
omc_control "$FILE_TYPE_ID" f
check "a real file type does"   "yes" "$(find_has_token -type)"
omc_control "$SIZE_COMPARE_ID" +
check "a real size comparison does" "yes" "$(find_has_token -size)"

section "size joins comparison, number and unit into one -size argument"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$SIZE_COMPARE_ID" +
omc_control "$SIZE_NUMBER_ID" 1000
omc_control "$SIZE_UNIT_ID" M
check "greater than"  "/usr/bin/find '$ROOT' -size +1000M -print" "$(find_command)"
omc_control "$SIZE_COMPARE_ID" -
check "less than"     "/usr/bin/find '$ROOT' -size -1000M -print" "$(find_command)"
# find spells "exactly" as a bare number, so the = comparison contributes nothing.
omc_control "$SIZE_COMPARE_ID" =
check "exactly"       "/usr/bin/find '$ROOT' -size 1000M -print"  "$(find_command)"
check "and find accepts it" "0" "$(find_run_built_command)"

section "a size comparison with no number is not a size clause"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$SIZE_COMPARE_ID" +
omc_control "$SIZE_NUMBER_ID" ""
check "no -size" "no" "$(find_has_token -size)"
omc_control "$SIZE_NUMBER_ID" 1
check "and with a number there is one" "yes" "$(find_has_token -size)"

section "size in bytes finds the files it should"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" f
omc_control "$SIZE_COMPARE_ID" +
omc_control "$SIZE_NUMBER_ID" 10
omc_control "$SIZE_UNIT_ID" c
check "only the long file is over 10 bytes" "$ROOT/TWO.TXT" "$(find_run_built_command_output)"

section "the emptiness test is a primary of its own"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" f
omc_control "$EMPTINESS_ID" -empty
check "empty files only" "$ROOT/sub/empty.txt" "$(find_run_built_command_output)"
omc_control "$EMPTINESS_ID" "-not -empty"
check "the negated form is two tokens" "yes" "$(find_has_token -not)"
check "and find accepts it"              "0" "$(find_run_built_command)"

section "permissions combine the ticked boxes into one -perm argument"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PERMISSIONS_COMPARE_ID" -
omc_control "$PERM_USER_READ_ID" true
omc_control "$PERM_USER_WRITE_ID" true
check "user read and write"  "/usr/bin/find '$ROOT' -perm '-u=rw' -print" "$(find_command)"
omc_control "$PERM_GROUP_READ_ID" true
check "a second class is comma separated" "/usr/bin/find '$ROOT' -perm '-u=rw,g=r' -print" \
    "$(find_command)"
omc_control "$PERM_OTHER_EXEC_ID" true
check "and a third"  "/usr/bin/find '$ROOT' -perm '-u=rw,g=r,o=x' -print" "$(find_command)"
# find spells an exact match as a bare mode, so the = comparison contributes nothing.
omc_control "$PERMISSIONS_COMPARE_ID" =
check "exact bit match drops the operator" "/usr/bin/find '$ROOT' -perm 'u=rw,g=r,o=x' -print" \
    "$(find_command)"

section "a permissions comparison with no box ticked is not a -perm clause"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PERMISSIONS_COMPARE_ID" -
check "no -perm" "no" "$(find_has_token -perm)"
omc_control "$PERM_USER_READ_ID" true
check "and one ticked box produces one" "yes" "$(find_has_token -perm)"

section "the permissions search really matches"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" f
omc_control "$PERMISSIONS_COMPARE_ID" =
omc_control "$PERM_USER_READ_ID" true
omc_control "$PERM_USER_WRITE_ID" true
check "only the 0600 file matches u=rw exactly" "$ROOT/sub/three.md" \
    "$(find_run_built_command_output)"

section "each time row maps to its own primary"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ATIME_CHOICE_ID" -
omc_control "$ATIME_NUMBER_ID" 5
check "last access is -atime"        "/usr/bin/find '$ROOT' -atime -5h -print" "$(find_command)"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$BTIME_CHOICE_ID" +
omc_control "$BTIME_NUMBER_ID" 2
omc_control "$BTIME_UNIT_ID" d
check "creation time is -Btime"      "/usr/bin/find '$ROOT' -Btime +2d -print" "$(find_command)"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$MTIME_CHOICE_ID" -
omc_control "$MTIME_NUMBER_ID" 1
omc_control "$MTIME_UNIT_ID" w
check "modification time is -mtime"  "/usr/bin/find '$ROOT' -mtime -1w -print" "$(find_command)"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$CTIME_CHOICE_ID" -
omc_control "$CTIME_NUMBER_ID" 30
omc_control "$CTIME_UNIT_ID" m
check "last status change is -ctime"  "/usr/bin/find '$ROOT' -ctime -30m -print" "$(find_command)"
check "and find accepts it"       "0" "$(find_run_built_command)"

section "a time row with no number is not a time clause"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$MTIME_CHOICE_ID" -
omc_control "$MTIME_NUMBER_ID" ""
check "no -mtime" "no" "$(find_has_token -mtime)"
omc_control "$MTIME_NUMBER_ID" 1
check "and with a number there is one" "yes" "$(find_has_token -mtime)"

section "the recently modified files really are found"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" f
omc_control "$MTIME_CHOICE_ID" -
omc_control "$MTIME_NUMBER_ID" 1
omc_control "$MTIME_UNIT_ID" h
check "everything just written is within the hour" "4" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "directory depth"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$DEPTH_MIN_ID" 1
omc_control "$DEPTH_MAX_ID" 1
check "both bounds"  "/usr/bin/find '$ROOT' -mindepth 1 -maxdepth 1 -print" "$(find_command)"
check "which is the top level only" "4" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "extended attributes: the three fixed choices, then a named attribute"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
check "Ignore adds nothing"  "/usr/bin/find '$ROOT' -print" "$(find_command)"
omc_control "$XATTR_ID" Any
check "Any is -xattr"        "/usr/bin/find '$ROOT' -xattr -print" "$(find_command)"
omc_control "$XATTR_ID" None
check "None is negated"      "/usr/bin/find '$ROOT' -not -xattr -print" "$(find_command)"
omc_control "$XATTR_ID" com.apple.FinderInfo
check "a name is -xattrname" "/usr/bin/find '$ROOT' -xattrname 'com.apple.FinderInfo' -print" \
    "$(find_command)"

section "the action picker chooses the primary, and -exec carries its tool"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ACTION_KIND_ID" -ls
check "list with ls"  "/usr/bin/find '$ROOT' -print -ls" "$(find_command)"
omc_control "$ACTION_KIND_ID" -print0
check "print0 does not also print" "/usr/bin/find '$ROOT' -print0" "$(find_command)"
check "and no separate -print was added" "no" "$(find_has_token -print)"
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" "/bin/echo {}"
check "exec gets its terminator" "/usr/bin/find '$ROOT' -print -exec /bin/echo {} ';'" \
    "$(find_command)"

section "Also print is what adds the extra -print, and only where it can"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ACTION_KIND_ID" -ls
omc_control "$ALSO_PRINT_ID" false
check "unchecked, ls alone" "/usr/bin/find '$ROOT' -ls" "$(find_command)"
omc_control "$ALSO_PRINT_ID" true
check "checked, print then ls" "/usr/bin/find '$ROOT' -print -ls" "$(find_command)"

section "-exec with no tool named contributes nothing"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" ""
check "no -exec"  "no" "$(find_has_token -exec)"
omc_control "$ACTION_TOOL_ID" "/bin/echo {}"
check "and with a tool there is one" "yes" "$(find_has_token -exec)"

section "-exec really runs the tool over what was found"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" f
omc_control "$PATTERN_ID" 'three.md'
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" "/bin/echo found: {}"
omc_control "$ALSO_PRINT_ID" false
check "echo ran once for the one match" "found: $ROOT/sub/three.md" \
    "$(find_run_built_command_output)"

section "the output section appends a shell redirection or pipe"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$OUTPUT_KIND_ID" "|"
omc_control "$OUTPUT_TARGET_ID" "/usr/bin/wc -l"
check "pipe to"  "/usr/bin/find '$ROOT' -print | /usr/bin/wc -l" "$(find_command)"
omc_control "$OUTPUT_KIND_ID" ">"
omc_control "$OUTPUT_TARGET_ID" "$OMCTEST_WORK/out.txt"
check "save to quotes the path" "/usr/bin/find '$ROOT' -print > '$OMCTEST_WORK/out.txt'" \
    "$(find_command)"
check "and the file really gets written" "0" "$(find_run_built_command)"
check "with every path in it" "8" \
    "$(/usr/bin/wc -l < "$OMCTEST_WORK/out.txt" | /usr/bin/tr -d ' ')"
omc_control "$OUTPUT_KIND_ID" "?"
omc_control "$OUTPUT_TARGET_ID" "| /usr/bin/wc -l"
check "custom is appended verbatim" "/usr/bin/find '$ROOT' -print | /usr/bin/wc -l" \
    "$(find_command)"

section "an output target with no kind chosen is ignored"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$OUTPUT_KIND_ID" "$NO_CHOICE_TAG"
omc_control "$OUTPUT_TARGET_ID" "/usr/bin/wc -l"
check "the target is not appended" "/usr/bin/find '$ROOT' -print" "$(find_command)"

section "a value carrying shell metacharacters is quoted, not interpolated"
# find.run.sh evals the command it builds, and control 1 now receives paths from
# outside the app via the drop handler. Wrapping a value in bare '...' is not
# escaping: an apostrophe ends the quote and everything after it becomes shell.
reset_controls_to_app_defaults
/bin/mkdir -p "$OMCTEST_WORK/Bob's Stuff"
omc_control "$LOCATION_ID" "$OMCTEST_WORK/Bob's Stuff"
check "an apostrophe is escaped in place" \
    "/usr/bin/find '$OMCTEST_WORK/Bob'\\''s Stuff' -print" "$(find_command)"
check "and find still accepts the command" "0" "$(find_run_built_command)"
check "and searches the folder that was named" "$OMCTEST_WORK/Bob's Stuff" \
    "$(find_run_built_command_output)"

reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
_canary="$OMCTEST_WORK/canary-was-run"
/bin/rm -f "$_canary"
omc_control "$PATTERN_ID" "x'\$(/usr/bin/touch $_canary)'y"
find_run_built_command >/dev/null
check_absent "a command substitution in a pattern did not run" "$_canary"
# Positive control: the canary really is reachable when something does run it.
( eval "/usr/bin/touch $_canary" )
check_exists "and the canary is otherwise writable" "$_canary"

section "everything at once still produces a command find accepts"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ALPHABETICAL_ID" true
omc_control "$PATTERN_ID" '*.txt'
omc_control "$FILE_TYPE_ID" f
omc_control "$SIZE_COMPARE_ID" +
omc_control "$SIZE_NUMBER_ID" 1
omc_control "$SIZE_UNIT_ID" c
omc_control "$MTIME_CHOICE_ID" -
omc_control "$MTIME_NUMBER_ID" 1
omc_control "$MTIME_UNIT_ID" w
omc_control "$DEPTH_MAX_ID" 2
check "the whole command" \
    "/usr/bin/find -s '$ROOT' -iname '*.txt' -type f -size +1c -mtime -1w -maxdepth 2 -print" \
    "$(find_command)"
check "find accepts it" "0" "$(find_run_built_command)"
check "and it finds the non-empty text files at depth 2" "2" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

omctest_end
