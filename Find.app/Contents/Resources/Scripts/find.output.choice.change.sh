#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

command=$(get_command_from_dialog_controls)
"$dialog" "$OMC_NIB_DLG_GUID" 3 "$command"

update_output_controls
