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

# Each combo box's dropdown is a companion Menu, so its contents are item Buttons
# rather than list rows: one omc_insert_element per item, not a table load.
#
# This is the one handler that runs before any dropdown holds an item, so it is also
# the only one allowed to read a missing snapshot as "nothing to remove first".
combo_menus_are_fresh=yes
set_all_combo_picker_options

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.all.controls"
