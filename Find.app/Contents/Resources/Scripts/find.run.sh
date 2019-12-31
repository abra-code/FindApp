#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

command=$(get_command_from_dialog_controls)
"$dialog" "$OMC_NIB_DLG_GUID" 3 "$command"

action_choice="$OMC_NIB_DIALOG_CONTROL_801_VALUE"
if [ "$action_choice" = "-delete" ]; then
	alert_message=$(echo "You are about to find and delete files. This operation cannot be undone!\n\nUse \"Print\" action first to verify which files will be removed.")
	"$OMC_OMC_SUPPORT_PATH/alert" --level caution --title "Deleting Files" --ok "Delete" --cancel "Cancel" "$alert_message"
	result=$?
	if [ $result -ne 0 ]; then
		echo "Cancelled"
		exit 1
	fi
fi

append_recent_item "recent_locations" 20 "$OMC_NIB_DIALOG_CONTROL_1_VALUE"
append_recent_item "recent_patterns" 20 "$OMC_NIB_DIALOG_CONTROL_102_VALUE"
if [ "$action_choice" = "-exec" ] || [ "$action_choice" = "-execdir" ]; then
	append_recent_item "recent_exec_scripts" 20 "$OMC_NIB_DIALOG_CONTROL_802_VALUE"
fi

output_choice="$OMC_NIB_DIALOG_CONTROL_901_VALUE"
if [ -n "$output_choice" ]; then
	append_recent_item "recent_output_scripts" 20 "$OMC_NIB_DIALOG_CONTROL_902_VALUE"
fi

extended_attribute_value="$OMC_NIB_DIALOG_CONTROL_202_VALUE"
if [ "$extended_attribute_value" != "Ignore" ]; then
	# Extended attributes combo is different because we want to keep the predefined menu items
	while IFS=$'\n' read -r one_item; do
		if [ "$extended_attribute_value" = "$one_item" ]; then
			# item exists in predefined extended list: don't add to recents
			extended_attribute_value=""
			break
		fi
	done < "$OMC_APP_BUNDLE_PATH/Contents/Resources/extended_attributes.txt"

	append_recent_item "recent_extended_attributes" 20 "$extended_attribute_value"
fi


#echo "Running command:"
#echo "$command"
eval "$command"
#/bin/sh -c "$command"
