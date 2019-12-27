#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

command=$(get_command_from_dialog_controls)
"$dialog" "$OMC_NIB_DLG_GUID" 3 "$command"

action_choice="$OMC_NIB_DIALOG_CONTROL_801_VALUE"
if [ "$action_choice" = "-delete" ]; then
	alert_message=$(echo "You are about to find and delete files. This operation cannot be undone!\n\nUse \"Print\" action first to verify which files will be removed.")
	"$OMC_OMC_SUPPORT_PATH/alert" --level caution --title "Deleting Files" --ok "Delete" --cancel "Cancel" "$alert_message"
	result=$?
	if test $result -ne 0; then
		echo "Cancelled"
		exit 1
	fi
fi

#echo "Running command:"
#echo "$command"
eval "$command"
#/bin/sh -c "$command"
