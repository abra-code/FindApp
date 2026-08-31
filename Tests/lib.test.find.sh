# Tests/lib.test.find.sh - Find's own test vocabulary, for omctest.
#
# Sourced after omctest.sh by every Tests/*.test.sh file. Holds the things the
# harness has no business knowing: how this applet spells its control values after
# the ActionUI port, and how to call into find.library.sh directly.
#
# The numbered files dispatch handlers and read the window back. 50-library.test.sh
# calls get_command_from_dialog_controls itself, because dispatching a handler and
# reading control 3 cannot distinguish "built the right find command" from "built a
# different one that happened to look right".

if [ "${OMCTEST_API_VERSION:-0}" -lt 4 ]; then
    printf 'lib.test.find: needs omctest API 4 or newer, found %s\n' \
        "${OMCTEST_API_VERSION:-none}" >&2
    exit 1
fi

APP_SCRIPTS="$OMCTEST_APP/Contents/Resources/Scripts"
APP_RESOURCES="$OMCTEST_APP/Contents/Resources"

# ---------------------------------------------------------------------------
# View ids, imported from the applet rather than restated here
# ---------------------------------------------------------------------------

# BSD sed has no \| alternation, so each rule gets its own -e.
omctest_import_view_ids() { # <script ...>
    local script
    for script; do
        eval "$(/usr/bin/sed -n \
            -e 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
            -e 's/^\(COMBO_PICKER_OFFSET\)=\([0-9][0-9]*\)$/\1=\2/p' \
            -e 's/^\(NO_CHOICE_TAG\)="\([^"]*\)"$/\1="\2"/p' \
            -e 's/^\(COMBO_ITEM_ID_BASE\)=\([0-9][0-9]*\)$/\1=\2/p' \
            -e 's/^\(COMBO_ITEM_ID_STRIDE\)=\([0-9][0-9]*\)$/\1=\2/p' \
            -e 's/^\(COMBO_FIELD_IDS\)="\(.*\)"$/\1="\2"/p' \
            "$script")"
    done
}
omctest_import_view_ids "$APP_SCRIPTS/find.library.sh"

# A name that failed to import expands to empty, omc_control then writes
# OMC_ACTIONUI_VIEW__VALUE, and every later check fails one by one with no hint why.
# Fail once, here, instead.
for _required in \
    LOCATION_ID CONFIG_ID COMMAND_PREVIEW_ID \
    PATTERN_KIND_ID PATTERN_ID CASE_SENSITIVE_ID USE_REGEX_ID ALPHABETICAL_ID \
    FILE_TYPE_ID XATTR_ID \
    SIZE_COMPARE_ID SIZE_NUMBER_ID SIZE_UNIT_ID EMPTINESS_ID \
    PERMISSIONS_COMPARE_ID PERMISSIONS_GRID_ID \
    DEPTH_MIN_ID DEPTH_MAX_ID STAY_ON_VOLUME_ID \
    CONTENT_ID CONTENT_CASE_SENSITIVE_ID CONTENT_USE_REGEX_ID CONTENT_SKIP_BINARY_ID \
    ACTION_KIND_ID ACTION_TOOL_ID ALSO_PRINT_ID \
    OUTPUT_KIND_ID OUTPUT_TARGET_ID \
    COMBO_PICKER_OFFSET NO_CHOICE_TAG COMBO_FIELD_IDS \
    COMBO_ITEM_ID_BASE COMBO_ITEM_ID_STRIDE
do
    eval "_value=\${$_required}"
    if [ -z "$_value" ]; then
        printf 'lib.test.find: %s did not import from find.library.sh\n' "$_required" >&2
        exit 1
    fi
done

# The permissions checkboxes are a 3x3 grid the applet addresses only by literal
# number, so the suite has to restate them. app_grid_ids_present below greps the
# applet for the same numbers, so drift shows up as a failure rather than silently.
PERM_USER_READ_ID=411
PERM_USER_WRITE_ID=412
PERM_USER_EXEC_ID=413
PERM_GROUP_READ_ID=421
PERM_GROUP_WRITE_ID=422
PERM_GROUP_EXEC_ID=423
PERM_OTHER_READ_ID=431
PERM_OTHER_WRITE_ID=432
PERM_OTHER_EXEC_ID=433

# Likewise the four time rows: choice, number, unit.
ATIME_CHOICE_ID=511
ATIME_NUMBER_ID=512
ATIME_UNIT_ID=513
BTIME_CHOICE_ID=521
BTIME_NUMBER_ID=522
BTIME_UNIT_ID=523
MTIME_CHOICE_ID=531
MTIME_NUMBER_ID=532
MTIME_UNIT_ID=533
CTIME_CHOICE_ID=541
CTIME_NUMBER_ID=542
CTIME_UNIT_ID=543

app_grid_ids_present() { # -> yes | no; the applet still names the ids restated above
    local one_id
    for one_id in $PERM_USER_READ_ID $PERM_OTHER_EXEC_ID $ATIME_CHOICE_ID $CTIME_UNIT_ID; do
        if ! /usr/bin/grep -q "OMC_ACTIONUI_VIEW_${one_id}_VALUE" "$APP_SCRIPTS/find.library.sh"; then
            echo no
            return 0
        fi
    done
    echo yes
}

combo_picker_id() { # <field-id>
    echo "$(( $1 + COMBO_PICKER_OFFSET ))"
}

# ---------------------------------------------------------------------------
# Calling into the applet's own library
# ---------------------------------------------------------------------------

# The subshell keeps the library's state out of the test file and stops a function
# that exits from taking the suite with it. Sourcing also runs the library's
# normalize_actionui_controls, which is exactly what happens in production.
find_call() { # <function> [argument ...]
    (
        . "$APP_SCRIPTS/find.library.sh" >/dev/null 2>&1
        "$@"
    )
}

# Needed whenever a call must name one of the library's own constants: the calling
# shell would expand it to empty before the subshell ever sources the library.
find_eval() { # <shell-text>
    (
        . "$APP_SCRIPTS/find.library.sh" >/dev/null 2>&1
        eval "$1"
    )
}

find_command() { # the find command line the current control values produce
    find_call get_command_from_dialog_controls
}

# Element match, never substring. "-print" is a substring of "-print0", and a
# substring check would report a primary the builder never emitted.
# set -f because the built command legitimately contains globs like *.txt, and
# unquoted word splitting would otherwise expand them against the cwd.
find_has_token() { # <token> -> yes | no
    local wanted="$1"
    local one_token
    set -f
    for one_token in $(find_command); do
        if [ "$one_token" = "$wanted" ]; then
            set +f
            echo yes
            return 0
        fi
    done
    set +f
    echo no
}

find_token_at() { # <1-based index> - order-sensitive assertion
    local wanted_index="$1"
    local index=0
    local one_token
    set -f
    for one_token in $(find_command); do
        index=$(( index + 1 ))
        if [ "$index" = "$wanted_index" ]; then
            set +f
            printf '%s' "$one_token"
            return 0
        fi
    done
    set +f
}

find_token_count() {
    local one_token
    local count=0
    set -f
    for one_token in $(find_command); do
        count=$(( count + 1 ))
    done
    set +f
    echo "$count"
}

# Run the built command for real. This is what makes the assertions worth anything:
# the string is not merely what was intended, it is one /usr/bin/find accepts.
# With a destructive action selected, the caller must have pointed the search at a
# throwaway tree first - the -delete sections here and in 60-run.test.sh do.
find_run_built_command() { # -> the command's exit status
    local command_text
    command_text=$(find_command)
    ( eval "$command_text" ) >/dev/null 2>&1
    printf '%s' "$?"
}

find_run_built_command_output() { # -> the command's stdout, sorted
    local command_text
    command_text=$(find_command)
    ( eval "$command_text" ) 2>/dev/null | /usr/bin/sort
}

# ---------------------------------------------------------------------------
# Applet state
# ---------------------------------------------------------------------------

app_support_dir() {
    printf '%s' "$HOME/Library/Application Support/com.abracode.Find"
}

configs_dir() {
    printf '%s' "$(app_support_dir)/Configs"
}

recents_file() { # <list name>
    printf '%s' "$(app_support_dir)/$1"
}

# Seed a recents list the way the applet's own append_recent_item would leave it.
write_recents() { # <list name> <item> ...
    local list_name="$1"
    shift
    /bin/mkdir -p "$(app_support_dir)"
    : > "$(recents_file "$list_name")"
    local one_item
    for one_item in "$@"; do
        printf '%s\n' "$one_item" >> "$(recents_file "$list_name")"
    done
}

write_config() { # <config name> <"id<TAB>value"> ...
    local config_name="$1"
    shift
    /bin/mkdir -p "$(configs_dir)"
    : > "$(configs_dir)/$config_name"
    local one_line
    for one_line in "$@"; do
        printf '%s\n' "$one_line" >> "$(configs_dir)/$config_name"
    done
}

config_value() { # <config name> <control id>
    local config_file="$(configs_dir)/$1"
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    /usr/bin/awk -F'\t' -v want="$2" '$1 == want { print $2 }' "$config_file"
}

# The value defaults.tsv declares for a control - the suite must not restate these.
declared_default() { # <control id>
    /usr/bin/awk -F'\t' -v want="$1" '$1 == want { print $3 }' "$APP_RESOURCES/defaults.tsv"
}

combo_item_id() { # <field-id> <0-based position>
    echo "$(( COMBO_ITEM_ID_BASE + $1 * COMBO_ITEM_ID_STRIDE + $2 ))"
}

# The Menu element the applet inserted into a combo's slot, as recorded by the
# harness. omc_insert_element is journaled, so the JSON is recoverable from there.
# The Button elements the applet appended to a combo's Menu, as recorded by the
# harness. omc_insert_element is journaled, so they are recoverable from there.
inserted_items_json() { # <field-id>
    # Assigning to $3 makes awk rebuild $0 with OFS and re-split it, so the second
    # substitution would act on a different field. Work on a copy.
    /usr/bin/awk -v menu="$(combo_picker_id "$1")" -F'\t' '
        $2 == menu && $3 ~ /^omc_insert_element / {
            record = $3
            sub(/^omc_insert_element /, "", record)
            sub(/ children append[ ]*$/, "", record)
            print record
        }' "$OMCTEST_UI/journal.tsv"
}

menu_item_count() { # <field-id>
    inserted_items_json "$1" | /usr/bin/grep -c . | /usr/bin/tr -d ' '
}

# ActionUI parses each of those before it renders anything, so validity has to be
# asserted here - the harness records the strings and never looks inside them.
menu_is_valid_json() { # <field-id> -> yes | no
    inserted_items_json "$1" | /usr/bin/python3 -c '
import json, sys
lines = [l for l in sys.stdin.read().split("\n") if l.strip()]
if not lines:
    print("no")
else:
    try:
        parsed = [json.loads(l) for l in lines]
    except Exception:
        print("no")
    else:
        print("yes" if all(p.get("type") == "Button" for p in parsed) else "no")
'
}

menu_offers() { # <field-id> <exact item text> -> yes | no
    OMCTEST_WANTED="$2"
    export OMCTEST_WANTED
    inserted_items_json "$1" | /usr/bin/python3 -c '
import json, os, sys
wanted = os.environ["OMCTEST_WANTED"]
found = False
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        item = json.loads(line)
    except Exception:
        continue
    if item.get("properties", {}).get("title") == wanted:
        found = True
print("yes" if found else "no")
'
}

# What the applet recorded as the list each dropdown was built from.
combo_snapshot() { # <field-id>
    /bin/cat "${TMPDIR:-/tmp}/com.abracode.Find.$OMC_ACTIONUI_WINDOW_UUID/combo.$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Resetting
# ---------------------------------------------------------------------------

# The window as it opens, before find.init has applied defaults.tsv. Starting from
# omc_reset_controls instead would describe a window where every picker is empty,
# which is a window no user has ever seen.
reset_window() {
    omc_control_defaults Find
    "$OMC_OMC_SUPPORT_PATH/pasteboard" "FIND_FOLDER_PATH" set "" >/dev/null 2>&1
    omc_object ""
    ui_reset
    alerts_reset
    alert_answers_reset
    chains_reset
}

# The control state a freshly initialized window has: the ActionUI document's
# declared defaults, then defaults.tsv over them - which is exactly the pair of
# steps find.init performs. Command-building tests start from here, because a
# window where every picker is empty is a window no user has ever seen.
reset_controls_to_app_defaults() {
    omc_control_defaults Find
    local control_id
    local control_key
    local default_value
    while IFS=$'\t' read -r control_id control_key default_value; do
        if [ -n "$control_id" ]; then
            omc_control "$control_id" "$default_value"
        fi
    done < "$APP_RESOURCES/defaults.tsv"
}

# handlers.log is append-only and shared by the whole file, so a bare grep would also
# match an earlier section. Mark before the dispatch, read only what came after.
handler_log_mark() {
    HANDLER_LOG_MARK=$(/usr/bin/wc -c < "$OMCTEST_UI/handlers.log" 2>/dev/null | /usr/bin/tr -d ' ')
    if [ -z "$HANDLER_LOG_MARK" ]; then
        HANDLER_LOG_MARK=0
    fi
}

handler_log_since() {
    /usr/bin/tail -c "+$(( ${HANDLER_LOG_MARK:-0} + 1 ))" "$OMCTEST_UI/handlers.log" 2>/dev/null
}

handler_log_mentions() { # <pattern> -> how many lines since the mark match
    handler_log_since | /usr/bin/grep -c "$1" | /usr/bin/tr -d ' '
}


# Where an item sits in the list the dropdown was built from. Tests name items by
# text; the menu addresses them by position, and this is the applet's own record of
# the mapping between the two.
combo_index_of() { # <field-id> <exact item text> -> 0-based position, or empty
    combo_snapshot "$1" | /usr/bin/grep -n -Fx -- "$2" | /usr/bin/head -1 |
        /usr/bin/cut -d: -f1 | {
            read -r line_number
            if [ -n "$line_number" ]; then
                echo "$(( line_number - 1 ))"
            fi
        }
}
