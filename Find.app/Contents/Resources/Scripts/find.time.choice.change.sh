#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

command=$(get_command_from_dialog_controls)
"$dialog" "$window_uuid" 3 "$command"

update_time_controls
