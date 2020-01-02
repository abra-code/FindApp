#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

config_name="$OMC_NIB_DIALOG_CONTROL_2_VALUE"
selected_config="$HOME/Library/Application Support/com.abracode.Find/Configs/$config_name"
if [ ! -f "$selected_config" ]; then
	echo "Could not find the selected config. Was it removed when the dialog was up?"
	exit 1
fi

# apply the defaults first
while IFS=$'\t' read -r CONTROL_ID OMC_NIB_CONTROL_KEY DEFAULT_VALUE; do
	"$dialog" "$OMC_NIB_DLG_GUID" "$CONTROL_ID" "$DEFAULT_VALUE"
done < "$OMC_APP_BUNDLE_PATH/Contents/Resources/defaults.tsv"

# and then the overrides
while IFS=$'\t' read -r CONTROL_ID CONTROL_VALUE; do
	"$dialog" "$OMC_NIB_DLG_GUID" "$CONTROL_ID" "$CONTROL_VALUE"
done < "$selected_config"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.all.controls"
