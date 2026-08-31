#!/bin/sh

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

config_name="$OMC_ACTIONUI_VIEW_2_VALUE"
if [ -z "$config_name" ]; then
	exit 0
fi

case "$config_name" in
	*/*)
		"$alert" --level caution --title "Find" --ok "OK" \
			"A config name cannot contain a slash."
		exit 1
		;;
esac

selected_config="$configs_dir/$config_name"
if [ ! -f "$selected_config" ]; then
	"$alert" --level caution --title "Find" --ok "OK" \
		"Could not find the config \"$config_name\". Was it removed while the window was open?"
	exit 1
fi

# apply the defaults first, so a config that omits a control still resets it
apply_control_defaults

# and then the overrides
while IFS=$'\t' read -r CONTROL_ID CONTROL_VALUE; do
	if [ -z "$CONTROL_ID" ]; then
		continue
	fi

	# A config written before the ActionUI port spells a checkbox "1"/"0" and an
	# unmade choice "". ActionUI accepts neither for those controls and drops the
	# write with no signal, which would silently leave the control at its default.
	case " $TOGGLE_IDS " in
		*" $CONTROL_ID "*)
			case "$CONTROL_VALUE" in
				1) CONTROL_VALUE="true" ;;
				0) CONTROL_VALUE="false" ;;
			esac
			;;
	esac
	case " $SENTINEL_PICKER_IDS " in
		*" $CONTROL_ID "*)
			if [ -z "$CONTROL_VALUE" ]; then
				CONTROL_VALUE="$NO_CHOICE_TAG"
			fi
			;;
	esac

	"$dialog" "$window_uuid" "$CONTROL_ID" "$CONTROL_VALUE"
done < "$selected_config"

"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.all.controls"
