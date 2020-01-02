#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

echo "find.init"

find_init_dir=""
if [ -n "$OMC_OBJ_PATH" ]; then
	find_init_dir="$OMC_OBJ_PATH"
else
	find_init_dir=$("$pasteboard" "FIND_FOLDER_PATH" get);
	"$pasteboard" "FIND_FOLDER_PATH" set ""
fi

app_support_dir="$HOME/Library/Application Support/com.abracode.Find"
configs_dir="$app_support_dir/Configs"
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

#echo "find_init_dir = $find_init_dir"
"$dialog" "$OMC_NIB_DLG_GUID" 1 "$find_init_dir"

# recent locations
/bin/cat "$recent_locations_path" | "$dialog" "$OMC_NIB_DLG_GUID" 1 omc_list_set_items_from_stdin

# recent name patterns
recent_patterns_path="$app_support_dir/recent_patterns"
/bin/cat "$recent_patterns_path" | "$dialog" "$OMC_NIB_DLG_GUID" 102 omc_list_set_items_from_stdin

# recent action/exec scripts
recent_exec_scripts_path="$app_support_dir/recent_exec_scripts"
/bin/cat "$recent_exec_scripts_path" | "$dialog" "$OMC_NIB_DLG_GUID" 802 omc_list_set_items_from_stdin

# recent output scripts
recent_output_scripts_path="$app_support_dir/recent_output_scripts"
/bin/cat "$recent_output_scripts_path" | "$dialog" "$OMC_NIB_DLG_GUID" 902 omc_list_set_items_from_stdin

# configs
/bin/ls "$configs_dir" | "$dialog" "$OMC_NIB_DLG_GUID" 2 omc_list_set_items_from_stdin

# recent extended attributes, combo box #202 is different because we want to keep pre-populated items
/bin/cat "$OMC_APP_BUNDLE_PATH/Contents/Resources/extended_attributes.txt" | "$dialog" "$OMC_NIB_DLG_GUID" 202 omc_list_set_items_from_stdin
recent_extended_attributes_path="$app_support_dir/recent_extended_attributes"
/bin/cat "$recent_extended_attributes_path" | "$dialog" "$OMC_NIB_DLG_GUID" 202 omc_list_append_items_from_stdin

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.all.controls"
