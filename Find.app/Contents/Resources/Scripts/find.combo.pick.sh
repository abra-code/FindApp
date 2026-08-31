#!/bin/sh
# A combo box is a TextField plus a companion Menu acting as its dropdown. Each menu
# item is a Button whose id encodes which combo it belongs to and its position in the
# list find.init built. This copies the chosen item into the field and then runs
# whatever the field's own action would have run.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

item_id="$OMC_ACTIONUI_TRIGGER_VIEW_ID"
if [ -z "$item_id" ]; then
	echo "find.combo.pick: no trigger view id"
	exit 1
fi

if [ "$item_id" -lt "$COMBO_ITEM_ID_BASE" ] 2>/dev/null; then
	echo "find.combo.pick: view $item_id is not a combo menu item"
	exit 1
fi

offset=$(( item_id - COMBO_ITEM_ID_BASE ))
field_id=$(( offset / COMBO_ITEM_ID_STRIDE ))
item_index=$(( offset % COMBO_ITEM_ID_STRIDE ))

case " $COMBO_FIELD_IDS " in
	*" $field_id "*)
		;;
	*)
		echo "find.combo.pick: view $item_id is not a combo menu item"
		exit 1
		;;
esac

# Resolve the position back to text through the snapshot find.init wrote, so a click
# always yields the line the user is looking at.
state_path="$(combo_state_dir)/combo.$field_id"
if [ ! -f "$state_path" ]; then
	echo "find.combo.pick: no item list for combo $field_id"
	exit 1
fi

picked_value=$(/usr/bin/sed -n "$(( item_index + 1 ))p" "$state_path")
if [ -z "$picked_value" ]; then
	echo "find.combo.pick: no item at position $item_index for combo $field_id"
	exit 1
fi

"$dialog" "$window_uuid" "$field_id" "$picked_value"

# The nib's combo boxes fired their own action on a dropdown selection. Only the
# Config combo did something other than refresh the command preview.
if [ "$field_id" = "$CONFIG_ID" ]; then
	"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.load.config"
else
	"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.output"
fi
