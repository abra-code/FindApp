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

if [ -z "$find_init_dir" ] && [ -f "/Users/$USER/Library/Preferences/com.abracode.find.plist" ]; then
	find_init_dir=$(/usr/bin/defaults read com.abracode.find LAST_DIR)
fi

if [ -n "$find_init_dir" ] && [ ! -d "$find_init_dir" ]; then
	find_init_dir=$(/usr/bin/dirname "$find_init_dir")
fi

if [ -z "$find_init_dir" ]; then
	find_init_dir="/Users/$USER"
fi

#echo "find_init_dir = $find_init_dir"
"$dialog" "$OMC_NIB_DLG_GUID" 1 "$find_init_dir"

find_support_dir="/Users/$USER/Library/Application Support/Find"
/bin/mkdir -p "$find_support_dir"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.all.controls"
