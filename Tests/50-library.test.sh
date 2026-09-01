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

# A foreign volume hanging below the search root, which is the shape issue #3
# describes. hdiutil attaches a disk image at an arbitrary mount point without root,
# so this needs nothing of the machine it runs on beyond a writable scratch dir.
XDEV_IMAGE="$OMCTEST_WORK/xdev.dmg"
XDEV_ROOT="$ROOT/mounted-volume"

XDEV_LOG="$OMCTEST_WORK/xdev.log"

xdev_mount() { # -> yes | no
    # Both modes mktemp a fresh scratch tree, so this cannot reach a previous run's
    # mount point - it guards the one case that can repeat, a deliberately reused
    # OMCTEST_SCRATCH, where hdiutil create would otherwise refuse to overwrite.
    xdev_unmount
    /bin/mkdir -p "$XDEV_ROOT"
    if ! /usr/bin/hdiutil create -size 2m -fs 'HFS+' -volname FindXdev -quiet \
            "$XDEV_IMAGE" >>"$XDEV_LOG" 2>&1; then
        xdev_unmount
        echo no
        return 0
    fi
    if ! /usr/bin/hdiutil attach -quiet -nobrowse -owners off \
            -mountpoint "$XDEV_ROOT" "$XDEV_IMAGE" >>"$XDEV_LOG" 2>&1; then
        xdev_unmount
        echo no
        return 0
    fi
    if ! printf 'x\n' > "$XDEV_ROOT/on-the-other-volume.txt" 2>>"$XDEV_LOG"; then
        xdev_unmount
        echo no
        return 0
    fi
    echo yes
}

xdev_unmount() {
    # An image left attached outlives the whole run: it holds the scratch dir open,
    # and because rm -rf crosses mount points the runner's cleanup would delete the
    # volume's contents and leave a device attached with no backing file. Force the
    # detach rather than let a busy mount block it. rmdir rather than rm -rf: it
    # refuses while anything is still mounted there, and the empty mount point has
    # to go or every later section counts one extra directory.
    if [ -d "$XDEV_ROOT" ]; then
        /usr/bin/hdiutil detach -quiet -force "$XDEV_ROOT" >/dev/null 2>&1
        # Report a mount that survived, not a detach that had nothing to do: the
        # failure paths above call this with the mount point created and nothing
        # mounted on it, and hdiutil returns non-zero for that too - which would
        # print a misleading line just before the real "could not mount" one. Once
        # this runs from the trap there is no check left between here and the rm -rf
        # that would cross into a volume still mounted, so that case does need saying.
        if [ "$(/usr/bin/stat -f '%d' "$XDEV_ROOT" 2>/dev/null)" \
             != "$(/usr/bin/stat -f '%d' "$ROOT" 2>/dev/null)" ]; then
            printf '50-library: could not detach %s\n' "$XDEV_ROOT" >&2
        fi
    fi
    /bin/rm -f "$XDEV_IMAGE"
    /bin/rmdir "$XDEV_ROOT" 2>/dev/null
    return 0
}

# The trap below has to detach the volume before anything runs rm -rf over the mount
# point, but installing it replaces whatever cleanup was already there - so ask what
# that was first and put it back. The harness only installs its own trap in this
# shell when it owns the scratch tree; under the runner, and when a caller hands it
# an existing OMCTEST_SCRATCH, it deliberately installs nothing, and calling its
# cleanup anyway would delete a directory that is not ours. Read the trap rather
# than infer it from the mode. Command substitution, never a pipeline: a subshell
# starts with the trap list cleared, so "trap -p EXIT | grep" always finds nothing.
case "$(trap -p EXIT)" in
    *omctest_cleanup_scratch*) xdev_displaced_cleanup=1 ;;
    *)                         xdev_displaced_cleanup=0 ;;
esac

# INT and TERM have to exit explicitly: a handler that merely returns lets the file
# carry on, which under Ctrl-C would run the remaining checks against a mount point
# the handler just detached.
xdev_at_exit() {
    xdev_unmount
    [ "$xdev_displaced_cleanup" = "0" ] || omctest_cleanup_scratch
}
trap 'xdev_at_exit' EXIT
trap 'xdev_at_exit; exit 130' INT
trap 'xdev_at_exit; exit 143' TERM

section "preconditions"
build_tree
check "the fixture tree was built" "yes" "$([ -d "$ROOT/sub/deeper" ] && echo yes || echo no)"
check "and it has a symlink"       "yes" "$([ -L "$ROOT/link.txt" ] && echo yes || echo no)"
check "/usr/bin/find is present"   "yes" "$([ -x /usr/bin/find ] && echo yes || echo no)"

section "an untouched window searches the location and prints"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
check "the whole command" "/usr/bin/find -x '$ROOT' -print" "$(find_command)"
check "and find accepts it"  "0" "$(find_run_built_command)"
check "and it walks the whole tree" "8" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "alphabetical order is a flag before the location, not after"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ALPHABETICAL_ID" true
# -x is on by default and would otherwise sit between the two tokens this section
# is about, which is what the next section but one exists to pin down.
omc_control "$STAY_ON_VOLUME_ID" false
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

section "staying on one volume is a flag before the location, and is the default"
# Issue #3: a search of /System/Volumes/Data descended into every external disk
# mounted beneath it. -x is find's own answer, and like -s it is an option rather
# than a primary, so it has to land before the path or find rejects the command.
# It is on out of the box because a search of a folder almost never means "and
# whatever happens to be mounted underneath it" - find's own default is the
# surprising one here.
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
check "on out of the box"    "yes" "$(find_has_token -x)"
check "the -x comes first"   "-x" "$(find_token_at 2)"
check "the location follows" "'$ROOT'" "$(find_token_at 3)"
check "find accepts it"       "0" "$(find_run_built_command)"
check "and it still walks the whole tree" "8" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "and it sorts after -s when both are on, which is the order find wants"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ALPHABETICAL_ID" true
omc_control "$STAY_ON_VOLUME_ID" true
check "the whole command" "/usr/bin/find -s -x '$ROOT' -print" "$(find_command)"
check "find accepts both"  "0" "$(find_run_built_command)"

section "the volume switch honors both Toggle spellings, as the others do"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$STAY_ON_VOLUME_ID" false
check "false really means off" "no" "$(find_has_token -x)"
omc_control "$STAY_ON_VOLUME_ID" 1
check "the old 1 spelling is honored" "yes" "$(find_has_token -x)"
omc_control "$STAY_ON_VOLUME_ID" 0
check "and the old 0 spelling too"     "no" "$(find_has_token -x)"

section "-x really keeps the search off another mounted volume"
# The reported bug is behavioral, not textual, and every check above would pass
# just as well against a build that emitted -x somewhere find quietly ignores.
# A 2MB disk image mounted inside the fixture reproduces the reporter's shape
# exactly - a foreign device hanging below the search root - without needing root
# or caring what is plugged into the machine.
check "a scratch volume mounted inside the tree" "yes" "$(xdev_mount)"
if [ -f "$XDEV_ROOT/on-the-other-volume.txt" ]; then
    check "the mount really is a different device" "yes" \
        "$([ "$(/usr/bin/stat -f '%d' "$ROOT")" != "$(/usr/bin/stat -f '%d' "$XDEV_ROOT")" ] \
            && echo yes || echo no)"

    reset_controls_to_app_defaults
    omc_control "$LOCATION_ID" "$ROOT"
    omc_control "$PATTERN_ID" 'on-the-other-volume.txt'
    omc_control "$STAY_ON_VOLUME_ID" false
    check "unchecked, the search escapes onto it" "$XDEV_ROOT/on-the-other-volume.txt" \
        "$(find_run_built_command_output)"

    omc_control "$STAY_ON_VOLUME_ID" true
    check "checked, it does not" "" "$(find_run_built_command_output)"

    # Positive control: -x must stop the descent at the mount point, not stop the
    # search. Without this, a build that emitted a flag making find return nothing
    # at all would pass the check above.
    omc_control "$PATTERN_ID" 'one.txt'
    check "while the same volume is still searched" "$ROOT/one.txt" \
        "$(find_run_built_command_output)"
else
    # hdiutil's own words, so the red check above is diagnosable rather than just red.
    printf '50-library: could not mount a scratch volume:\n%s\n' \
        "$(/bin/cat "$XDEV_LOG" 2>/dev/null)" >&2
fi

# Outside the if, so an unmountable machine does not also leak the mount point, and
# asserted rather than discarded: a mount point left behind would otherwise surface
# much later as three unrelated file-count failures with nothing pointing back here.
xdev_unmount
check "the scratch volume was detached and its mount point removed" "no" \
    "$([ -e "$XDEV_ROOT" ] && echo yes || echo no)"

section "the name pattern picks its primary from the kind, case and regex switches"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PATTERN_ID" '*.txt'
check "name, case-insensitive"  "/usr/bin/find -x '$ROOT' -iname '*.txt' -print" "$(find_command)"
omc_control "$CASE_SENSITIVE_ID" true
check "name, case-sensitive"    "/usr/bin/find -x '$ROOT' -name '*.txt' -print"  "$(find_command)"
omc_control "$CASE_SENSITIVE_ID" false
omc_control "$PATTERN_KIND_ID" -ipath
check "full path, case-insensitive" "/usr/bin/find -x '$ROOT' -ipath '*.txt' -print" "$(find_command)"
omc_control "$USE_REGEX_ID" true
check "full path as a regex adds -E" "/usr/bin/find -x -E '$ROOT' -iregex '*.txt' -print" \
    "$(find_command)"
omc_control "$CASE_SENSITIVE_ID" true
check "and case-sensitive regex"     "/usr/bin/find -x -E '$ROOT' -regex '*.txt' -print" \
    "$(find_command)"

section "-E is the one option -x has to sit beside, so run that combination for real"
# The two checks above assert a string only: "*.txt" is not a valid ERE, so find
# rejects the command and neither shape is ever executed. -x -E and -s -x -E are
# the orderings the option block can produce that nothing else in this file runs.
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$PATTERN_KIND_ID" -ipath
omc_control "$USE_REGEX_ID" true
omc_control "$PATTERN_ID" '.*\.txt'
check "find accepts -x alongside -E" "0" "$(find_run_built_command)"
# one.txt, TWO.TXT (the regex is the case-insensitive -iregex here), link.txt and
# sub/empty.txt - the whole path is matched, not just the last component.
check "and the regex really matched" "4" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
omc_control "$ALPHABETICAL_ID" true
check "and alongside both -s and -E"  "0" "$(find_run_built_command)"
check "in that order"  "/usr/bin/find -s -x -E '$ROOT' -iregex '.*\.txt' -print" \
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
check "regular files"       "/usr/bin/find -x '$ROOT' -type f -print" "$(find_command)"
omc_control "$FILE_TYPE_ID" '!d'
check "not directories" "/usr/bin/find -x '$ROOT' -not -type d -print" "$(find_command)"
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
check "the sentinel adds nothing anywhere" "/usr/bin/find -x '$ROOT' -print" "$(find_command)"
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
check "greater than"  "/usr/bin/find -x '$ROOT' -size '+1000M' -print" "$(find_command)"
omc_control "$SIZE_COMPARE_ID" -
check "less than"     "/usr/bin/find -x '$ROOT' -size '-1000M' -print" "$(find_command)"
# find spells "exactly" as a bare number, so the = comparison contributes nothing.
omc_control "$SIZE_COMPARE_ID" =
check "exactly"       "/usr/bin/find -x '$ROOT' -size '1000M' -print"  "$(find_command)"
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
check "user read and write"  "/usr/bin/find -x '$ROOT' -perm '-u=rw' -print" "$(find_command)"
omc_control "$PERM_GROUP_READ_ID" true
check "a second class is comma separated" "/usr/bin/find -x '$ROOT' -perm '-u=rw,g=r' -print" \
    "$(find_command)"
omc_control "$PERM_OTHER_EXEC_ID" true
check "and a third"  "/usr/bin/find -x '$ROOT' -perm '-u=rw,g=r,o=x' -print" "$(find_command)"
# find spells an exact match as a bare mode, so the = comparison contributes nothing.
omc_control "$PERMISSIONS_COMPARE_ID" =
check "exact bit match drops the operator" "/usr/bin/find -x '$ROOT' -perm 'u=rw,g=r,o=x' -print" \
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
check "last access is -atime"        "/usr/bin/find -x '$ROOT' -atime '-5h' -print" "$(find_command)"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$BTIME_CHOICE_ID" +
omc_control "$BTIME_NUMBER_ID" 2
omc_control "$BTIME_UNIT_ID" d
check "creation time is -Btime"      "/usr/bin/find -x '$ROOT' -Btime '+2d' -print" "$(find_command)"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$MTIME_CHOICE_ID" -
omc_control "$MTIME_NUMBER_ID" 1
omc_control "$MTIME_UNIT_ID" w
check "modification time is -mtime"  "/usr/bin/find -x '$ROOT' -mtime '-1w' -print" "$(find_command)"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$CTIME_CHOICE_ID" -
omc_control "$CTIME_NUMBER_ID" 30
omc_control "$CTIME_UNIT_ID" m
check "last status change is -ctime"  "/usr/bin/find -x '$ROOT' -ctime '-30m' -print" "$(find_command)"
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
check "both bounds"  "/usr/bin/find -x '$ROOT' -mindepth '1' -maxdepth '1' -print" "$(find_command)"
check "which is the top level only" "4" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "extended attributes: the three fixed choices, then a named attribute"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
check "Ignore adds nothing"  "/usr/bin/find -x '$ROOT' -print" "$(find_command)"
omc_control "$XATTR_ID" Any
check "Any is -xattr"        "/usr/bin/find -x '$ROOT' -xattr -print" "$(find_command)"
omc_control "$XATTR_ID" None
check "None is negated"      "/usr/bin/find -x '$ROOT' -not -xattr -print" "$(find_command)"
omc_control "$XATTR_ID" com.apple.FinderInfo
check "a name is -xattrname" "/usr/bin/find -x '$ROOT' -xattrname 'com.apple.FinderInfo' -print" \
    "$(find_command)"

# ---------------------------------------------------------------------------
# Content search
# ---------------------------------------------------------------------------
# A tree of its own, because the sections above assert exact file counts against
# build_tree and adding files to it would move every one of them. Every name here is
# deliberately unrelated to what is inside the file, so a content match cannot be
# passing on the strength of the name filter.
CROOT="$OMCTEST_WORK/content"

build_content_tree() {
    /bin/rm -rf "$CROOT"
    /bin/mkdir -p "$CROOT/sub"
    printf 'the needle is nested\n' > "$CROOT/sub/nested.txt"
    printf 'the needle is in here\n'  > "$CROOT/aaa.txt"
    printf 'nothing of interest\n'    > "$CROOT/bbb.txt"
    printf 'a NEEDLE, shouting\n'     > "$CROOT/ccc.txt"
    printf 'version 42 shipped\n'     > "$CROOT/ddd.txt"
    printf 'abc\n'                    > "$CROOT/eee.txt"
    printf 'a.c\n'                    > "$CROOT/fff.txt"
    # NUL bytes are what make grep call a file binary - control characters alone do
    # not, so \001\002 here would leave the -I section asserting nothing.
    /usr/bin/printf 'needle\000\000tail\n' > "$CROOT/ggg.bin"
}

arm_content() {
    reset_controls_to_app_defaults
    build_content_tree
    omc_control "$LOCATION_ID" "$CROOT"
}

# The same, but bounded. check() does not abort a file, so a regression that makes the
# grep block would stall the whole run with no failure line naming the cause - this
# turns that into an ordinary failed comparison.
#
# The output goes to a FILE, never a pipe. alarm survives exec and does kill the shell
# on time, but the grep it left behind is still blocked on the pipe and still holds the
# write end, so a "| sort" here would go on waiting long after the alarm fired. Writing
# to a file lets this return at the deadline and read back whatever was produced.
content_hits_bounded() { # <seconds>
    local bounded_out="$OMCTEST_WORK/bounded-hits"
    local bounded_rc
    /bin/rm -f "$bounded_out" "$OMCTEST_WORK/bounded-timedout"
    /usr/bin/perl -e 'alarm shift; exec @ARGV' "$1" \
        /bin/sh -c "$(find_command)" > "$bounded_out" 2>/dev/null
    bounded_rc=$?
    # Death by signal is the deadline. Record it in a file, not a variable: this runs
    # inside a command substitution, so a variable would not survive back to the caller.
    if [ "$bounded_rc" -ge 128 ]; then
        : > "$OMCTEST_WORK/bounded-timedout"
    fi
    /usr/bin/sort "$bounded_out" | /usr/bin/sed "s|^$CROOT/||" | /usr/bin/tr '\n' ' ' \
        | /usr/bin/sed 's/ $//'
}

# Basenames of what the built command finds, so the assertions read as file lists.
content_hits() {
    find_run_built_command_output | /usr/bin/sed "s|^$CROOT/||" | /usr/bin/tr '\n' ' ' \
        | /usr/bin/sed 's/ $//'
}

section "with no content pattern the command carries no content test at all"
arm_content
check "no -exec"  "no" "$(find_has_token -exec)"
check "no grep"   "no" "$(find_has_token /usr/bin/grep)"
check "the command is untouched" "/usr/bin/find -x '$CROOT' -print" "$(find_command)"

section "a content pattern becomes an -exec condition, placed after every other test"
# -exec is find's own idiom for a test: the command's exit status is the result, so
# the match filters like -size does instead of consuming the action.
arm_content
omc_control "$CONTENT_ID" "needle"
check "the whole command" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -print" \
    "$(find_command)"
check "find accepts it" "0" "$(find_run_built_command)"

section "and it really filters on content rather than on the name"
# Every filename in this tree is unrelated to its contents, so a name-based
# implementation would return all of them or none.
arm_content
omc_control "$CONTENT_ID" "needle"
check "only the files that contain it" "aaa.txt ccc.txt sub/nested.txt" "$(content_hits)"

section "the content match is case-insensitive by default, like the name match"
arm_content
omc_control "$CONTENT_ID" "NEEDLE"
check "either case matches" "aaa.txt ccc.txt sub/nested.txt" "$(content_hits)"
omc_control "$CONTENT_CASE_SENSITIVE_ID" true
check "until case sensitivity is asked for" "ccc.txt" "$(content_hits)"
check "and then -i is gone" "no" "$(find_has_token -i)"

section "unchecked means literally literal, not a bare grep's BRE"
# The trap this section exists for: plain grep is BRE, where "." is still a
# metacharacter, so "a.c" would match "abc" and the unchecked box would be a lie.
arm_content
omc_control "$CONTENT_ID" 'a.c'
check "the dot is just a dot" "fff.txt" "$(content_hits)"
check "which is -F"           "yes" "$(find_has_token -F)"
check "and never -E"           "no" "$(find_has_token -E)"

section "and checked means extended regex"
omc_control "$CONTENT_USE_REGEX_ID" true
check "the dot matches any character" "eee.txt fff.txt" "$(content_hits)"
check "which is -E" "yes" "$(find_has_token -E)"
check "and not -F"   "no" "$(find_has_token -F)"
# A pattern only ERE can express, so this cannot pass on -F semantics by accident.
arm_content
omc_control "$CONTENT_USE_REGEX_ID" true
omc_control "$CONTENT_ID" 'version [0-9]+'
check "a real regex works" "ddd.txt" "$(content_hits)"

section "skipping binary files is on out of the box, and can be turned off"
arm_content
omc_control "$CONTENT_ID" "needle"
check "the binary file is not offered" "aaa.txt ccc.txt sub/nested.txt" "$(content_hits)"
check "because of -I"            "yes" "$(find_has_token -I)"
omc_control "$CONTENT_SKIP_BINARY_ID" false
check "unchecked, it matches too" "aaa.txt ccc.txt ggg.bin sub/nested.txt" "$(content_hits)"
check "and -I is gone"            "no" "$(find_has_token -I)"

section "a blank line in the pattern is not an alternative that matches everything"
# grep reads each line of -e as its own pattern, so one blank line among them matches
# every file - "find the files containing X" becomes "list everything", silently.
arm_content
omc_control "$CONTENT_ID" "$(printf 'needle\n\nzzz-no-such-text')"
check "only the real matches come back" "aaa.txt ccc.txt sub/nested.txt" "$(content_hits)"
# Blank, not merely empty: a space-only line is an alternative that matches any file
# containing a space, which is very nearly everything.
arm_content
omc_control "$CONTENT_ID" "$(printf 'needle\n \nzzz-no-such-text')"
check "a space-only line counts as blank" "aaa.txt ccc.txt sub/nested.txt" \
    "$(content_hits)"
# The CRLF form of the same paste. The blank line goes, but the CR that LF left on the
# line before it does not, so "needle\r" no longer matches a Unix file and the search
# comes back empty. That is the safe direction to be wrong in - too strict rather than
# matching every file - and it is the behavior, so it is what this pins.
arm_content
omc_control "$CONTENT_ID" "$(printf 'needle\r\n\r\nzzz-no-such-text')"
check "a CRLF paste does not match everything" "" "$(content_hits)"
# The control that gives that check its meaning: without the blank line dropped, the
# empty alternative would have returned the whole tree rather than nothing.
check "and specifically is not the whole tree" "no" \
    "$([ "$(content_hits)" = "aaa.txt bbb.txt ccc.txt ddd.txt eee.txt fff.txt ggg.bin sub/nested.txt" ] \
        && echo yes || echo no)"
# But a single line is the pattern the user meant, whatever is in it - there are no
# alternatives to be empty, so a deliberate search for whitespace still works.
arm_content
printf 'has\ttab\n' > "$CROOT/iii.txt"
omc_control "$CONTENT_ID" "$(printf '\t')"
check "a lone whitespace pattern is preserved" "iii.txt" "$(content_hits)"

section "a pattern that reduces to nothing emits no content test, and no stray -print"
# The -print fallback keys off what was actually emitted, not off the raw field: if it
# keyed off the field, this state would append a -print with no content test in front
# of it. Reachable only if a newline can get into the field at all, which is exactly
# why the guard above exists.
# A value of nothing but newlines cannot be used here - it reaches the handler as the
# empty string, so it would exercise the same path an untouched field does and prove
# nothing. Whitespace-only lines are the discriminating case: non-empty on the way in,
# nothing at all once the blank lines are dropped.
arm_content
omc_control "$CONTENT_ID" "$(printf ' \n \n ')"
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" ""
omc_control "$ALSO_PRINT_ID" false
check "the field really did arrive non-empty" "yes" \
    "$([ -n "$OMC_ACTIONUI_VIEW_701_VALUE" ] && echo yes || echo no)"
check "no content test" "no" "$(find_has_token /usr/bin/grep)"
check "and no -print to go with it" "no" "$(find_has_token -print)"
check "which is the bare search" "/usr/bin/find -x '$CROOT'" "$(find_command)"

section "the content test never runs grep on something that cannot be read"
# grep blocks in read() on a FIFO and never returns, and macOS really does put them
# in a home directory, so without -type f a content search of $HOME hangs with no
# error at all. The mkfifo below is that hang, made reproducible.
arm_content
/usr/bin/mkfifo "$CROOT/a-pipe" 2>/dev/null
# Without this the section is green while asserting nothing: a failed mkfifo leaves an
# ordinary tree that every check below passes on.
check "the pipe is really there" "yes" \
    "$([ -p "$CROOT/a-pipe" ] && echo yes || echo no)"
omc_control "$CONTENT_ID" "needle"
# The whole command, not a token: find_has_token -type is an element match on "-type"
# alone, so it answers yes to "! -type d" too - and "! -type d" still hangs. That is
# the natural simplification someone reaches for to remove the -type d contradiction
# the next section pins, so the check guarding against it has to tell the two apart.
check "-type f guards the grep" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -print" \
    "$(find_command)"
check "and the search completes rather than hanging" "aaa.txt ccc.txt sub/nested.txt" \
    "$(content_hits_bounded 20)"
# Only when the search above really did time out. A grep is then still blocked opening
# the pipe and would outlive the whole run, and opening the write end releases it.
#
# Strictly conditional, and bounded, because the reverse is just as bad: on the passing
# path -type f means nothing ever opens the pipe, so this open would find no reader and
# block forever - and unlinking a FIFO does not wake a blocked open, so an unconditional
# background version leaks one immortal shell per run.
if [ -f "$OMCTEST_WORK/bounded-timedout" ]; then
    /usr/bin/perl -e 'alarm 5; open(my $fh, ">", $ARGV[0]);' "$CROOT/a-pipe" 2>/dev/null
    /bin/rm -f "$OMCTEST_WORK/bounded-timedout"
fi
/bin/rm -f "$CROOT/a-pipe"

section "asking for directories and for contents finds nothing, rather than hanging"
# The two conditions contradict each other - a directory has no contents to match -
# and an empty result is the honest answer. Pinned so the -type f guard above cannot
# be quietly dropped to make this case "work".
arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$FILE_TYPE_ID" d
check "nothing matches" "" "$(content_hits)"
# "Not regular files" is the same contradiction spelled the other way round.
omc_control "$FILE_TYPE_ID" '!f'
check "nor for the negated form" "" "$(content_hits)"
# And symbolic links, where grep would otherwise read through to the target - which is
# what would reopen the hang, since a link can point at a FIFO.
omc_control "$FILE_TYPE_ID" l
check "nor for symbolic links" "" "$(content_hits)"
# And the picker's own "Regular files" leaves no duplicate token behind.
omc_control "$FILE_TYPE_ID" f
check "while asking for files emits -type f once" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -print" \
    "$(find_command)"

section "a content search still prints when the action slot emits nothing"
# find only supplies an implicit -print when the expression has no -exec of its own,
# and the content test is an -exec. Choosing "Execute tool", leaving the tool empty
# and unticking "Also print" is a reachable state, and it used to turn a content
# search into a command that printed nothing at all.
arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" ""
omc_control "$ALSO_PRINT_ID" false
check "there is still a -print" "yes" "$(find_has_token -print)"
check "and the matches really come out" "aaa.txt ccc.txt sub/nested.txt" "$(content_hits)"
# Negative control: with no content pattern the same state emits no -print, because
# find's own implicit one is still in force and adding a second would be noise.
arm_content
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" ""
omc_control "$ALSO_PRINT_ID" false
check "which is not added when there is no content test" "no" "$(find_has_token -print)"
check "because find still prints by itself there" "10" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "the content test in the combinations the emission order could break"
arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$ACTION_KIND_ID" -print0
check "with -print0" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -print0" \
    "$(find_command)"
check "which find accepts" "0" "$(find_run_built_command)"

arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" "/bin/echo {}"
omc_control "$ALSO_PRINT_ID" false
check "beside a second -exec whose tool also uses {}" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -exec /bin/echo {} ';'" \
    "$(find_command)"
check "and both {} resolve independently" "aaa.txt ccc.txt sub/nested.txt" "$(content_hits)"

arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$CONTENT_CASE_SENSITIVE_ID" true
check "and case-sensitive drops only the -i" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -F -I -e 'needle' {} ';' -print" \
    "$(find_command)"

arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$OUTPUT_KIND_ID" "|"
omc_control "$OUTPUT_TARGET_ID" "/usr/bin/wc -l"
check "and the output pipe still hangs off the end" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -print | /usr/bin/wc -l" \
    "$(find_command)"
check "which counts the matches" "3" \
    "$(find_run_built_command_output | /usr/bin/tr -d ' ')"

section "the content test composes with an action instead of replacing one"
# The reason for making this a test rather than an action: "delete every file whose
# contents match" stays one find command.
arm_content
omc_control "$CONTENT_ID" "needle"
omc_control "$ACTION_KIND_ID" -delete
omc_control "$ALSO_PRINT_ID" false
check "the action still follows the test" \
    "/usr/bin/find -x '$CROOT' -type f -exec /usr/bin/grep -q -i -F -I -e 'needle' {} ';' -delete" \
    "$(find_command)"
find_run_built_command >/dev/null
check "only the matching files were deleted" "bbb.txt ddd.txt eee.txt fff.txt ggg.bin" \
    "$(/usr/bin/find "$CROOT" -type f | /usr/bin/sed "s|^$CROOT/||" | /usr/bin/sort \
        | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"

section "and it narrows the name filter rather than replacing it"
arm_content
omc_control "$PATTERN_ID" 'aaa*'
omc_control "$CONTENT_ID" "needle"
check "both conditions have to hold" "aaa.txt" "$(content_hits)"
omc_control "$CONTENT_ID" "nothing of interest"
check "a name hit with the wrong contents is dropped" "" "$(content_hits)"

section "a content pattern is quoted, so it cannot break out into the shell"
# Control 701 feeds the same eval every other field does.
arm_content
_canary="$OMCTEST_WORK/content-canary"
/bin/rm -f "$_canary"
omc_control "$CONTENT_ID" "x'; /usr/bin/touch $_canary; echo '"
find_run_built_command >/dev/null
check_absent "the injected command did not run" "$_canary"
# Positive control: the pattern really did reach the command, quoted, rather than the
# whole content test having been dropped - which would pass the check above for the
# wrong reason.
check "the content test was still built" "yes" "$(find_has_token /usr/bin/grep)"
check "with the quote escaped, not honored" "1" \
    "$(find_command | /usr/bin/grep -c "'\\\\''")"
# A pattern full of shell metacharacters survives as a literal search term.
arm_content
printf 'cost is $100 (approx)\n' > "$CROOT/hhh.txt"
omc_control "$CONTENT_ID" 'cost is $100 (approx)'
check "metacharacters are searched for, not interpreted" "hhh.txt" "$(content_hits)"

section "the action picker chooses the primary, and -exec carries its tool"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ACTION_KIND_ID" -ls
check "list with ls"  "/usr/bin/find -x '$ROOT' -print -ls" "$(find_command)"
omc_control "$ACTION_KIND_ID" -print0
check "print0 does not also print" "/usr/bin/find -x '$ROOT' -print0" "$(find_command)"
check "and no separate -print was added" "no" "$(find_has_token -print)"
omc_control "$ACTION_KIND_ID" -exec
omc_control "$ACTION_TOOL_ID" "/bin/echo {}"
check "exec gets its terminator" "/usr/bin/find -x '$ROOT' -print -exec /bin/echo {} ';'" \
    "$(find_command)"

section "Also print is what adds the extra -print, and only where it can"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ACTION_KIND_ID" -ls
omc_control "$ALSO_PRINT_ID" false
check "unchecked, ls alone" "/usr/bin/find -x '$ROOT' -ls" "$(find_command)"
omc_control "$ALSO_PRINT_ID" true
check "checked, print then ls" "/usr/bin/find -x '$ROOT' -print -ls" "$(find_command)"

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
check "pipe to"  "/usr/bin/find -x '$ROOT' -print | /usr/bin/wc -l" "$(find_command)"
omc_control "$OUTPUT_KIND_ID" ">"
omc_control "$OUTPUT_TARGET_ID" "$OMCTEST_WORK/out.txt"
check "save to quotes the path" "/usr/bin/find -x '$ROOT' -print > '$OMCTEST_WORK/out.txt'" \
    "$(find_command)"
check "and the file really gets written" "0" "$(find_run_built_command)"
check "with every path in it" "8" \
    "$(/usr/bin/wc -l < "$OMCTEST_WORK/out.txt" | /usr/bin/tr -d ' ')"
omc_control "$OUTPUT_KIND_ID" "?"
omc_control "$OUTPUT_TARGET_ID" "| /usr/bin/wc -l"
check "custom is appended verbatim" "/usr/bin/find -x '$ROOT' -print | /usr/bin/wc -l" \
    "$(find_command)"

section "an output target with no kind chosen is ignored"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$OUTPUT_KIND_ID" "$NO_CHOICE_TAG"
omc_control "$OUTPUT_TARGET_ID" "/usr/bin/wc -l"
check "the target is not appended" "/usr/bin/find -x '$ROOT' -print" "$(find_command)"

section "a value carrying shell metacharacters is quoted, not interpolated"
# find.run.sh evals the command it builds, and control 1 now receives paths from
# outside the app via the drop handler. Wrapping a value in bare '...' is not
# escaping: an apostrophe ends the quote and everything after it becomes shell.
reset_controls_to_app_defaults
/bin/mkdir -p "$OMCTEST_WORK/Bob's Stuff"
omc_control "$LOCATION_ID" "$OMCTEST_WORK/Bob's Stuff"
check "an apostrophe is escaped in place" \
    "/usr/bin/find -x '$OMCTEST_WORK/Bob'\\''s Stuff' -print" "$(find_command)"
check "and find still accepts the command" "0" "$(find_run_built_command)"
check "and searches the folder that was named" "$OMCTEST_WORK/Bob's Stuff" \
    "$(find_run_built_command_output)"

reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
_canary="$OMCTEST_WORK/canary-was-run"
/bin/rm -f "$_canary"
# Two payloads in one, because there are two ways this can regress and they need
# opposite shapes. If shell_quote is dropped and the value is interpolated bare, the
# unquoted "$(...)" runs; if it is dropped and the site goes back to wrapping the
# value in its own '...' - which is the bug this helper was written for - the
# apostrophes in the first half close that wrapping and the substitution inside runs.
# Either payload alone passes against the other mutation, which is a check that
# cannot fail for half the cases it claims to cover.
omc_control "$PATTERN_ID" "x'\$(/usr/bin/touch $_canary)'z\$(/usr/bin/touch $_canary)y"
find_run_built_command >/dev/null
check_absent "a command substitution in a pattern did not run" "$_canary"
# Positive control: the canary really is reachable when something does run it.
( eval "/usr/bin/touch $_canary" )
check_exists "and the canary is otherwise writable" "$_canary"

# The number fields are text fields like any other. Nothing about them enforces a
# number: the prompt says "N", the control accepts anything, and a saved config or
# a recent item can put a value there without anyone typing it.
#
# The payloads below carry no apostrophe on purpose. These sites were interpolated
# bare rather than wrapped in quotes the value could close, so the shape that breaks
# out is a plain ";" or "$(...)" - an apostrophe here would only be swallowed as a
# literal and the check would pass whether or not the quoting is there. Each of the
# three was confirmed to go red with shell_quote removed from its own call site.
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
/bin/rm -f "$_canary"
omc_control "$DEPTH_MAX_ID" "1\$(/usr/bin/touch $_canary)"
find_run_built_command >/dev/null
check_absent "a command substitution in a depth bound did not run" "$_canary"

reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
/bin/rm -f "$_canary"
omc_control "$SIZE_COMPARE_ID" +
omc_control "$SIZE_NUMBER_ID" "1; /usr/bin/touch $_canary; echo "
find_run_built_command >/dev/null
check_absent "a statement separator in a size number did not either" "$_canary"

reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
/bin/rm -f "$_canary"
omc_control "$MTIME_CHOICE_ID" -
omc_control "$MTIME_NUMBER_ID" "1\$(/usr/bin/touch $_canary)"
find_run_built_command >/dev/null
check_absent "nor one in a time number" "$_canary"
# Positive control again, since three checks above depend on this canary path.
( eval "/usr/bin/touch $_canary" )
check_exists "and that canary is reachable too" "$_canary"

section "an unknown Picker tag is dropped rather than emitted"
# A Picker looks like a closed set, but ActionUI stores whatever string it is handed
# (Picker declares parseStringValue = nil), and find.load.config.sh writes any value
# a config file names into any control id. So these arrive from outside exactly the
# way a text field does. They cannot be quoted - their tags are multi-word find
# primaries - so find.library.sh allow-lists them instead.
_canary="$OMCTEST_WORK/picker-canary"

check_picker_tag_rejected() {
    reset_controls_to_app_defaults
    omc_control "$LOCATION_ID" "$ROOT"
    omc_control "$PATTERN_ID" 'zzz'
    # The output clause is only emitted when BOTH the kind and the target are set,
    # so the target has to be filled in or the 901 case would pass by never having
    # built the clause at all.
    omc_control "$OUTPUT_TARGET_ID" '/usr/bin/wc -l'
    /bin/rm -f "$_canary"
    omc_control "$1" "$2"
    find_run_built_command >/dev/null
    check_absent "$3" "$_canary"
}

check_picker_tag_rejected "$FILE_TYPE_ID"   "d; /usr/bin/touch $_canary; #" \
    "a planted file type ran nothing"
check_picker_tag_rejected "$EMPTINESS_ID"   "-empty; /usr/bin/touch $_canary; #" \
    "nor a planted emptiness test"
check_picker_tag_rejected "$ACTION_KIND_ID" "-print; /usr/bin/touch $_canary; #" \
    "nor a planted action"
check_picker_tag_rejected "$PATTERN_KIND_ID" "-name zzz; /usr/bin/touch $_canary; #" \
    "nor a planted pattern kind"
check_picker_tag_rejected "$OUTPUT_KIND_ID" "; /usr/bin/touch $_canary; #" \
    "nor a planted output kind"
# Positive control: this canary path is writable, so the five checks above are not
# passing because nothing could ever have created the file.
( eval "/usr/bin/touch $_canary" )
check_exists "and the picker canary is reachable" "$_canary"

# The allow-list must not have made the legitimate tags unreachable.
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$FILE_TYPE_ID" '!f'
check "a real negated file type still works" \
    "/usr/bin/find -x '$ROOT' -not -type f -print" "$(find_command)"
omc_control "$FILE_TYPE_ID" "$NO_CHOICE_TAG"
omc_control "$EMPTINESS_ID" '-not -empty'
check "and a two-word emptiness test still works" \
    "/usr/bin/find -x '$ROOT' -not -empty -print" "$(find_command)"

section "everything at once still produces a command find accepts"
reset_controls_to_app_defaults
omc_control "$LOCATION_ID" "$ROOT"
omc_control "$ALPHABETICAL_ID" true
omc_control "$STAY_ON_VOLUME_ID" true
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
    "/usr/bin/find -s -x '$ROOT' -iname '*.txt' -type f -size '+1c' -mtime '-1w' -maxdepth '2' -print" \
    "$(find_command)"
check "find accepts it" "0" "$(find_run_built_command)"
check "and it finds the non-empty text files at depth 2" "2" \
    "$(find_run_built_command_output | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

omctest_end
