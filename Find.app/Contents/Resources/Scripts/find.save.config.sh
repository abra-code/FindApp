#!/bin/sh

config_name="$OMC_NIB_DIALOG_CONTROL_2_VALUE"
selected_config="$HOME/Library/Application Support/com.abracode.Find/Configs/$config_name"
rm "$selected_config"

while IFS=$'\t' read -r CONTROL_ID OMC_NIB_CONTROL_KEY DEFAULT_VALUE; do
	# obtain current control value for each key stored in "defaults.tsv"
	# this is done by double dereference with ${!KEY} below
	NIB_CONTROL_VALUE="${!OMC_NIB_CONTROL_KEY}"
	printf "$CONTROL_ID\t$NIB_CONTROL_VALUE\n" >> "$selected_config"
done < "$OMC_APP_BUNDLE_PATH/Contents/Resources/defaults.tsv"
