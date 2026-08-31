#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

update_pattern_controls
update_action_controls
update_output_controls
update_permissions_controls
update_size_controls
update_time_controls

# The dropdowns are part of "all controls": saving a config adds one to the Config
# list, and this is what puts it in the menu without the window being reopened. Each
# one that did not change is left untouched, so the usual case costs nothing.
set_all_combo_picker_options

command=$(get_command_from_dialog_controls)
"$dialog" "$window_uuid" 3 "$command"
