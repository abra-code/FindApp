#!/bin/sh
# Saves the current control values under the name typed in the Config combo.
#
# This handler deliberately does NOT source find.library.sh. That library normalizes
# ActionUI values on the way in - "none" becomes "" and "true" becomes "1" - which is
# right for building a find command and wrong for a config file, because a config is
# replayed through omc_dialog_control and ActionUI only accepts its own spellings.
# Everything here therefore reads the raw environment.

config_name="$OMC_ACTIONUI_VIEW_2_VALUE"
if [ -z "$config_name" ]; then
	"$OMC_OMC_SUPPORT_PATH/alert" --level caution --title "Find" --ok "OK" \
		"Name the config before saving it."
	exit 1
fi

case "$config_name" in
	*/*)
		"$OMC_OMC_SUPPORT_PATH/alert" --level caution --title "Find" --ok "OK" \
			"A config name cannot contain a slash."
		exit 1
		;;
esac

configs_dir="$HOME/Library/Application Support/com.abracode.Find/Configs"
/bin/mkdir -p "$configs_dir"
selected_config="$configs_dir/$config_name"
partial_config="$selected_config.saving.$$"
/bin/rm -f "$partial_config"

while IFS=$'\t' read -r CONTROL_ID CONTROL_KEY DEFAULT_VALUE; do
	if [ -z "$CONTROL_ID" ]; then
		continue
	fi
	# defaults.tsv is app-owned, but this value is about to be dereferenced by name
	case "$CONTROL_KEY" in
		OMC_ACTIONUI_VIEW_*_VALUE)
			;;
		*)
			continue
			;;
	esac
	# obtain the current value for each key named in defaults.tsv
	eval "CONTROL_VALUE=\$$CONTROL_KEY"
	# %s, never the value as a format string: a value containing % is legitimate
	printf '%s\t%s\n' "$CONTROL_ID" "$CONTROL_VALUE" >> "$partial_config"
done < "$OMC_APP_BUNDLE_PATH/Contents/Resources/defaults.tsv"

# rename last, so an interrupted save leaves the previous config intact
/bin/mv "$partial_config" "$selected_config"
