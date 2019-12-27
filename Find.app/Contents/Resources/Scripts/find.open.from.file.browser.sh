#!/bin/sh

# this handler is called when the Open menu item is selected
if [ -n "$OMC_DLG_CHOOSE_FOLDER_PATH" ]; then
	"$OMC_OMC_SUPPORT_PATH/pasteboard" "FIND_FOLDER_PATH" put "$OMC_DLG_CHOOSE_FOLDER_PATH";
	"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "find.new"
fi
