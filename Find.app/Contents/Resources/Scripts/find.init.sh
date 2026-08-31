#!/bin/sh
# Runs as the ActionUI window's INIT_SUBCOMMAND_ID, before the window is shown.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

# The window opens on each Picker's first option, which is not always the documented
# default, so seed every control from defaults.tsv before anything else.
apply_control_defaults

find_init_dir=""
if [ -n "$OMC_OBJ_PATH" ]; then
	find_init_dir="$OMC_OBJ_PATH"
else
	find_init_dir=$("$pasteboard" "FIND_FOLDER_PATH" get);
	"$pasteboard" "FIND_FOLDER_PATH" set ""
fi

/bin/mkdir -p "$configs_dir"
recent_locations_path="$app_support_dir/recent_locations"

if [ -z "$find_init_dir" ] && [ -f "$recent_locations_path" ]; then
	find_init_dir=$(/usr/bin/head -n 1 "$recent_locations_path")
fi

if [ -n "$find_init_dir" ] && [ ! -d "$find_init_dir" ]; then
	find_init_dir=$(/usr/bin/dirname "$find_init_dir")
fi

if [ -z "$find_init_dir" ]; then
	find_init_dir="/Users/$USER"
fi

"$dialog" "$window_uuid" "$LOCATION_ID" "$find_init_dir"

# Each combo box's dropdown is a companion Picker, so its contents are options rather
# than list items: one omc_set_property per combo, not omc_list_set_items_from_stdin.
set_combo_picker_options "$LOCATION_ID" "$recent_locations_path"
set_combo_picker_options "$PATTERN_ID" "$app_support_dir/recent_patterns"
set_combo_picker_options "$ACTION_TOOL_ID" "$app_support_dir/recent_exec_scripts"
set_combo_picker_options "$OUTPUT_TARGET_ID" "$app_support_dir/recent_output_scripts"

# Configs are listed from the directory rather than a recents file.
configs_list=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/find.configs.XXXXXX")
/bin/ls "$configs_dir" > "$configs_list" 2>/dev/null
set_combo_picker_options "$CONFIG_ID" "$configs_list"
/bin/rm -f "$configs_list"

# The extended attributes combo keeps its shipped list and appends the recents to it.
set_combo_picker_options "$XATTR_ID" \
	"$extended_attributes_path" \
	"$app_support_dir/recent_extended_attributes"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.all.controls"
