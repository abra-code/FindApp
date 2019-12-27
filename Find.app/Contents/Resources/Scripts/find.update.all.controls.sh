#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

update_pattern_controls
update_action_controls
update_output_controls
update_permissions_controls
update_size_controls
update_time_controls

command=$(get_command_from_dialog_controls)
"$dialog" "$OMC_NIB_DLG_GUID" 3 "$command"
