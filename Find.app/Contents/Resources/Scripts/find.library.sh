#!/bin/sh
# find.library.sh - shared helpers for the Find applet's handlers.
#
# POSIX sh only: OMC runs .sh handlers under /bin/sh, which is bash 3.2 in POSIX
# mode. Validate with "sh -n", never "bash -n".

dialog="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
plister="$OMC_OMC_SUPPORT_PATH/plister"
filt="$OMC_OMC_SUPPORT_PATH/filt"
pasteboard="$OMC_OMC_SUPPORT_PATH/pasteboard"
next_command="$OMC_OMC_SUPPORT_PATH/omc_next_command"
alert="$OMC_OMC_SUPPORT_PATH/alert"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

app_support_dir="$HOME/Library/Application Support/com.abracode.Find"
configs_dir="$app_support_dir/Configs"
defaults_path="$OMC_APP_BUNDLE_PATH/Contents/Resources/defaults.tsv"
extended_attributes_path="$OMC_APP_BUNDLE_PATH/Contents/Resources/extended_attributes.txt"

# Control ids. These are the "id" values in Base.lproj/Find.json, and they are the
# tags the old nib dialog used - kept identical through the ActionUI port so that
# config files written by older builds still name the same controls.
LOCATION_ID=1
CONFIG_ID=2
COMMAND_PREVIEW_ID=3
PATTERN_KIND_ID=101
PATTERN_ID=102
CASE_SENSITIVE_ID=103
USE_REGEX_ID=104
ALPHABETICAL_ID=111
STAY_ON_VOLUME_ID=112
FILE_TYPE_ID=201
XATTR_ID=202
SIZE_COMPARE_ID=301
SIZE_NUMBER_ID=302
SIZE_UNIT_ID=303
EMPTINESS_ID=304
PERMISSIONS_COMPARE_ID=401
PERMISSIONS_GRID_ID=402
DEPTH_MIN_ID=611
DEPTH_MAX_ID=612
ACTION_KIND_ID=801
ACTION_TOOL_ID=802
ALSO_PRINT_ID=803
OUTPUT_KIND_ID=901
OUTPUT_TARGET_ID=902

# A combo box has no ActionUI equivalent, so each one is a TextField carrying the
# legacy id plus a companion dropdown at COMBO_PICKER_OFFSET + that id. The dropdown
# is a Menu rather than a Picker: a menu-style Picker reserves a fixed leading inset
# for its hidden title, which leaves the chevron visibly off-centre in a button this
# narrow. A Menu draws only its label, so the glyph centres.
#
# The JSON declares an empty slot at that id; find.init inserts the whole Menu, with
# every item, in one call. Each item Button carries an id encoding which combo it
# belongs to and its position in the list, and find.combo.pick resolves that back to
# the item text through the snapshot init wrote.
COMBO_PICKER_OFFSET=1000
COMBO_ITEM_ID_BASE=100000
COMBO_ITEM_ID_STRIDE=100
COMBO_FIELD_IDS="$LOCATION_ID $CONFIG_ID $PATTERN_ID $XATTR_ID $ACTION_TOOL_ID $OUTPUT_TARGET_ID"

# ActionUI refuses a Picker option whose tag is empty, so every menu item that
# meant "no choice" in the nib carries this sentinel tag instead.
NO_CHOICE_TAG="none"
SENTINEL_PICKER_IDS="$FILE_TYPE_ID $SIZE_COMPARE_ID $EMPTINESS_ID $PERMISSIONS_COMPARE_ID 511 521 531 541 $OUTPUT_KIND_ID"

# ActionUI Toggles carry a Bool, so they arrive as "true"/"false" where the nib
# checkboxes arrived as "1"/"0".
TOGGLE_IDS="$CASE_SENSITIVE_ID $USE_REGEX_ID $ALPHABETICAL_ID $STAY_ON_VOLUME_ID 411 412 413 421 422 423 431 432 433 $ALSO_PRINT_ID"

# Restate the two ActionUI value conventions above in the form the rest of this
# library was written against: "" for no choice, "1"/"0" for a checkbox. Doing it
# once here keeps every downstream [ -n "$choice" ] and [ "$flag" = "1" ] correct.
normalize_actionui_controls()
{
	local control_id
	local control_value
	for control_id in $SENTINEL_PICKER_IDS; do
		eval "control_value=\$OMC_ACTIONUI_VIEW_${control_id}_VALUE"
		if [ "$control_value" = "$NO_CHOICE_TAG" ]; then
			eval "OMC_ACTIONUI_VIEW_${control_id}_VALUE=''"
		fi
	done

	for control_id in $TOGGLE_IDS; do
		eval "control_value=\$OMC_ACTIONUI_VIEW_${control_id}_VALUE"
		case "$control_value" in
			true|TRUE|1)
				eval "OMC_ACTIONUI_VIEW_${control_id}_VALUE=1"
				;;
			*)
				eval "OMC_ACTIONUI_VIEW_${control_id}_VALUE=0"
				;;
		esac
	done
}

normalize_actionui_controls

# Wrap a value as a single-quoted shell word. The find command is assembled as text
# and handed to eval, so writing '$value' is not escaping: an apostrophe in a folder
# name breaks the command, and since a dropped path now reaches control 1 from
# outside, "evil'$(...)'x" would otherwise run arbitrary shell.
shell_quote()
{
	printf "'%s'" "$(printf '%s' "$1" | /usr/bin/sed "s/'/'\\\\''/g")"
}

get_command_from_dialog_controls()
{
	local output_command="/usr/bin/find"
	local start_dir="$OMC_ACTIONUI_VIEW_1_VALUE"
	#local config_name="$OMC_ACTIONUI_VIEW_2_VALUE"
	#local output_command="$OMC_ACTIONUI_VIEW_3_VALUE"
	
	local use_alphabetical_order="$OMC_ACTIONUI_VIEW_111_VALUE"
	if [ "$use_alphabetical_order" = "1" ]; then
		output_command="$output_command -s"
	fi

	# -x is an option, not a primary, so it belongs before the path like -s does.
	# It stops the descent at any directory whose device number differs from the one
	# it started on, which is what keeps a search of /System/Volumes/Data off the
	# external disks mounted underneath it.
	local stay_on_volume="$OMC_ACTIONUI_VIEW_112_VALUE"
	if [ "$stay_on_volume" = "1" ]; then
		output_command="$output_command -x"
	fi

	local pattern="$OMC_ACTIONUI_VIEW_102_VALUE"
	if [ -n "$pattern" ]; then
		local pattern_choice="$OMC_ACTIONUI_VIEW_101_VALUE"
		local pattern_case_sensitive="$OMC_ACTIONUI_VIEW_103_VALUE"
		if [ "$pattern_choice" = "-iname" ]; then
			if [ "$pattern_case_sensitive" = "1" ]; then
				pattern_choice="-name"
			fi
		elif [ "$pattern_choice" = "-ipath" ]; then
			local pattern_regex="$OMC_ACTIONUI_VIEW_104_VALUE"
			if [ "$pattern_regex" = "1" ]; then
				pattern_choice="-iregex"
			fi
			if [ "$pattern_case_sensitive" = "1" ]; then
				if [ "$pattern_regex" = "1" ]; then
					pattern_choice="-regex"
				else
					pattern_choice="-path"
				fi
			fi
		fi

		if [ "$pattern_regex" = 1 ]; then
			#only extended regexes supported
			output_command="$output_command -E"
		fi

		output_command="$output_command $(shell_quote "$start_dir") $pattern_choice $(shell_quote "$pattern")"
	else
		output_command="$output_command $(shell_quote "$start_dir")"
	fi


	local file_type="$OMC_ACTIONUI_VIEW_201_VALUE"
	if [ -n "$file_type" ]; then
		local primary_type="-type"
		#the following works with both bash and zsh
		if [[ "$file_type" = '!'* ]]; then
			primary_type="-not -type"
			file_type=$(echo "$file_type" | /usr/bin/tr -d '!')
		fi
		output_command="$output_command $primary_type $file_type"
	fi
		
	local primary_xattr=""
	local extended_attributes="$OMC_ACTIONUI_VIEW_202_VALUE"
	if [ "$extended_attributes" = "Ignore" ]; then
		primary_xattr=""
	elif [ "$extended_attributes" = "Any" ]; then
		primary_xattr="-xattr"
	elif [ "$extended_attributes" = "None" ]; then
		primary_xattr="-not -xattr"
	elif [ -n "$extended_attributes" ]; then
		output_command="$output_command -xattrname $(shell_quote "$extended_attributes")"
	fi

	if [ -n "$primary_xattr" ]; then
		output_command="$output_command $primary_xattr"
	fi

	local size_choice="$OMC_ACTIONUI_VIEW_301_VALUE"
	local size_number="$OMC_ACTIONUI_VIEW_302_VALUE"
	if [ -n "$size_choice" ] && [ -n "$size_number" ]; then
		if [ "$size_choice" = "=" ]; then
			size_choice=""
		fi
		local size_scale="$OMC_ACTIONUI_VIEW_303_VALUE"
		output_command="$output_command -size $size_choice$size_number$size_scale"
	fi

	local size_empy_test="$OMC_ACTIONUI_VIEW_304_VALUE"
	if [ -n "$size_empy_test" ]; then
		output_command="$output_command $size_empy_test"
	fi

	local permissions_choice="$OMC_ACTIONUI_VIEW_401_VALUE"
	if [ -n "$permissions_choice" ]; then
		if [ "$permissions_choice" = "=" ]; then
			permissions_choice=""
		fi
		
		perm_user=""
		local permissions_user_read="$OMC_ACTIONUI_VIEW_411_VALUE"
		local permissions_user_write="$OMC_ACTIONUI_VIEW_412_VALUE"
		local permissions_user_exec="$OMC_ACTIONUI_VIEW_413_VALUE"
		if [ "$permissions_user_read" = "1" ] || [ "$permissions_user_write" = "1" ] || [ "$permissions_user_exec" = "1" ]; then
			perm_user="u="
			if [ "$permissions_user_read" = "1" ]; then
				perm_user="${perm_user}r"
			fi
			if [ "$permissions_user_write" = "1" ]; then
				perm_user="${perm_user}w"
			fi
			if [ "$permissions_user_exec" = "1" ]; then
				perm_user="${perm_user}x"
			fi
		fi
		
		perm_group=""
		local permissions_group_read="$OMC_ACTIONUI_VIEW_421_VALUE"
		local permissions_group_write="$OMC_ACTIONUI_VIEW_422_VALUE"
		local permissions_group_exec="$OMC_ACTIONUI_VIEW_423_VALUE"
		if [ "$permissions_group_read" = "1" ] || [ "$permissions_group_write" = "1" ] || [ "$permissions_group_exec" = "1" ]; then
			perm_group="g="
			if [ "$permissions_group_read" = "1" ]; then
				perm_group="${perm_group}r"
			fi
			if [ "$permissions_group_write" = "1" ]; then
				perm_group="${perm_group}w"
			fi
			if [ "$permissions_group_exec" = "1" ]; then
				perm_group="${perm_group}x"
			fi
		fi

		perm_other=""
		local permissions_other_read="$OMC_ACTIONUI_VIEW_431_VALUE"
		local permissions_other_write="$OMC_ACTIONUI_VIEW_432_VALUE"
		local permissions_other_exec="$OMC_ACTIONUI_VIEW_433_VALUE"
		if [ "$permissions_other_read" = "1" ] || [ "$permissions_other_write" = "1" ] || [ "$permissions_other_exec" = "1" ]; then
			perm_other="o="
			if [ "$permissions_other_read" = "1" ]; then
				perm_other="${perm_other}r"
			fi
			if [ "$permissions_other_write" = "1" ]; then
				perm_other="${perm_other}w"
			fi
			if [ "$permissions_other_exec" = "1" ]; then
				perm_other="${perm_other}x"
			fi
		fi

		perm_combined="$perm_user"
		if [ -n "$perm_group" ]; then
			if [ -n "$perm_combined" ]; then
				perm_combined="$perm_combined,"
			fi
			perm_combined="$perm_combined$perm_group"
		fi

		if [ -n "$perm_other" ]; then
			if [ -n "$perm_combined" ]; then
				perm_combined="$perm_combined,"
			fi
			perm_combined="$perm_combined$perm_other"
		fi

		if [ -n "$perm_combined" ]; then
			output_command="$output_command -perm $(shell_quote "$permissions_choice$perm_combined")"
		fi
	fi

	local time_access_choice="$OMC_ACTIONUI_VIEW_511_VALUE"
	local time_access_number="$OMC_ACTIONUI_VIEW_512_VALUE"
	if [ -n "$time_access_choice" ] && [ -n "$time_access_number" ]; then
		local time_access_unit="$OMC_ACTIONUI_VIEW_513_VALUE"
		output_command="$output_command -atime $time_access_choice$time_access_number$time_access_unit"
	fi
	
	local time_creation_choice="$OMC_ACTIONUI_VIEW_521_VALUE"
	local time_creation_number="$OMC_ACTIONUI_VIEW_522_VALUE"
	if [ -n "$time_creation_choice" ] && [ -n "$time_creation_number" ]; then
		local time_creation_unit="$OMC_ACTIONUI_VIEW_523_VALUE"
		output_command="$output_command -Btime $time_creation_choice$time_creation_number$time_creation_unit"
	fi

	local time_modification_choice="$OMC_ACTIONUI_VIEW_531_VALUE"
	local time_modification_number="$OMC_ACTIONUI_VIEW_532_VALUE"
	if [ -n "$time_modification_choice" ] && [ -n "$time_modification_number" ]; then
		local time_modification_unit="$OMC_ACTIONUI_VIEW_533_VALUE"
		output_command="$output_command -mtime $time_modification_choice$time_modification_number$time_modification_unit"
	fi

	local time_status_choice="$OMC_ACTIONUI_VIEW_541_VALUE"
	local time_status_number="$OMC_ACTIONUI_VIEW_542_VALUE"
	if [ -n "$time_status_choice" ] && [ -n "$time_status_number" ]; then
		local time_status_unit="$OMC_ACTIONUI_VIEW_543_VALUE"
		output_command="$output_command -ctime $time_status_choice$time_status_number$time_status_unit"
	fi

	local depth_min="$OMC_ACTIONUI_VIEW_611_VALUE"
	if [ -n "$depth_min" ]; then
		output_command="$output_command -mindepth $depth_min"
	fi
	
	local depth_max="$OMC_ACTIONUI_VIEW_612_VALUE"
	if [ -n "$depth_max" ]; then
		output_command="$output_command -maxdepth $depth_max"
	fi
	
	local action_choice="$OMC_ACTIONUI_VIEW_801_VALUE"
	local action_also_print="$OMC_ACTIONUI_VIEW_803_VALUE"
	if [ "$action_also_print" = "1" ] && [ "$action_choice" != "-print" ] && [ "$action_choice" != "-print0" ]; then
		output_command="$output_command -print"
	fi

	if [ "$action_choice" = "-exec" -o  "$action_choice" = "-execdir" ]; then
		local action_exec_tool="$OMC_ACTIONUI_VIEW_802_VALUE"
		if [ -n "$action_exec_tool" ]; then
			output_command="$output_command $action_choice $action_exec_tool ';'"
		fi
	elif [ -n "$action_choice" ]; then
		output_command="$output_command $action_choice"
	fi
	
	local output_choice="$OMC_ACTIONUI_VIEW_901_VALUE"
	local output_script="$OMC_ACTIONUI_VIEW_902_VALUE"
	if [ -n "$output_choice" ] && [ -n "$output_script" ]; then
		if [ "$output_choice" = ">" ]; then
			output_command="$output_command > $(shell_quote "$output_script")"
		elif  [ "$output_choice" = "?" ]; then
			output_command="$output_command $output_script"
		else
			output_command="$output_command $output_choice $output_script"
		fi
	fi
	
	echo "$output_command"
}

update_pattern_controls()
{
	local pattern_choice="$OMC_ACTIONUI_VIEW_101_VALUE"
	if [ "$pattern_choice" = "-ipath" ]; then
		"$dialog" "$window_uuid" 104 omc_enable
	else
		"$dialog" "$window_uuid" 104 omc_disable
	fi
}

update_action_controls()
{
	local action_choice="$OMC_ACTIONUI_VIEW_801_VALUE"
	if [ "$action_choice" = "-print" -o "$action_choice" = "-print0" -o "$action_choice" = "-ls" -o "$action_choice" = "-delete" ]; then
		"$dialog" "$window_uuid" 802 omc_disable
	else
		"$dialog" "$window_uuid" 802 omc_enable
	fi
	
	if [ "$action_choice" = "-print" -o "$action_choice" = "-print0" ]; then
		"$dialog" "$window_uuid" 803 omc_disable
	else
		"$dialog" "$window_uuid" 803 omc_enable
	fi	
}

update_output_controls()
{
	local output_choice="$OMC_ACTIONUI_VIEW_901_VALUE"
	if [ -n "$output_choice" ]; then
		"$dialog" "$window_uuid" 902 omc_enable
	else
		"$dialog" "$window_uuid" 902 omc_disable
	fi
}

update_size_controls()
{
	local size_choice="$OMC_ACTIONUI_VIEW_301_VALUE"
	if [ -n "$size_choice" ]; then
		"$dialog" "$window_uuid" 302 omc_enable
		"$dialog" "$window_uuid" 303 omc_enable
	else
		"$dialog" "$window_uuid" 302 omc_disable
		"$dialog" "$window_uuid" 303 omc_disable
	fi
}

update_permissions_controls()
{
	local permissions_choice="$OMC_ACTIONUI_VIEW_401_VALUE"
	if [ -n "$permissions_choice" ]; then
		"$dialog" "$window_uuid" 402 omc_enable
	else
	 	"$dialog" "$window_uuid" 402 omc_disable
	fi
}


update_time_controls()
{
	local time_access_choice="$OMC_ACTIONUI_VIEW_511_VALUE"
	if [ -n "$time_access_choice" ]; then
		"$dialog" "$window_uuid" 512 omc_enable
		"$dialog" "$window_uuid" 513 omc_enable
	else
		"$dialog" "$window_uuid" 512 omc_disable
		"$dialog" "$window_uuid" 513 omc_disable
	fi
	
	local time_creation_choice="$OMC_ACTIONUI_VIEW_521_VALUE"
	if [ -n "$time_creation_choice" ]; then
		"$dialog" "$window_uuid" 522 omc_enable
		"$dialog" "$window_uuid" 523 omc_enable
	else
		"$dialog" "$window_uuid" 522 omc_disable
		"$dialog" "$window_uuid" 523 omc_disable
	fi

	local time_modification_choice="$OMC_ACTIONUI_VIEW_531_VALUE"
	if [ -n "$time_modification_choice" ]; then
		"$dialog" "$window_uuid" 532 omc_enable
		"$dialog" "$window_uuid" 533 omc_enable
	else
		"$dialog" "$window_uuid" 532 omc_disable
		"$dialog" "$window_uuid" 533 omc_disable
	fi

	local time_status_choice="$OMC_ACTIONUI_VIEW_541_VALUE"
	if [ -n "$time_status_choice" ]; then
		"$dialog" "$window_uuid" 542 omc_enable
		"$dialog" "$window_uuid" 543 omc_enable
	else
		"$dialog" "$window_uuid" 542 omc_disable
		"$dialog" "$window_uuid" 543 omc_disable
	fi
}

append_recent_item()
{
	local list_name="$1"
	local max_count="$2"
	local recent_item="$3"

	# do not add empty items
	if [ -z "$recent_item" ]; then
		return 0
	fi

	local recent_list_path="$app_support_dir/$list_name"

	# On a first run none of these lists exist yet, and the read loop below needs
	# something to redirect from.
	/bin/mkdir -p "$app_support_dir"
	if [ ! -f "$recent_list_path" ]; then
		: > "$recent_list_path"
	fi

	local recent_items_array
	# the new item might be a duplicate of an existing item in array
	recent_items_array=( "$recent_item" )
	local one_item
	while IFS=$'\n' read -r one_item; do
		if [ "$recent_item" != "$one_item" ]; then
			recent_items_array+=("$one_item")
		fi
	done < "$recent_list_path"
	
	local array_count=${#recent_items_array[@]}
	if [ "$array_count" -gt "$max_count" ]; then
		array_count="$max_count"
	fi
	
	/bin/rm -f "$recent_list_path"

	# in bash array index starts with 0 but in zsh it starts with 1!
	# in macOS 10.15 Catalina zsh is the default shell but it does not change /bin/sh
	# which is still bash
	local line_index=0
	while [ "$line_index" -lt "$array_count" ]; do
		echo "${recent_items_array[$line_index]}" >> "$recent_list_path"
		let "line_index++"
	done
}


# Push every control back to the value defaults.tsv declares. ActionUI Pickers have
# no initial-selection property - they open on their first option - so this is also
# what gives the size unit "MB" and the four time units "hours" when the window opens.
apply_control_defaults()
{
	local control_id
	local control_key
	local default_value
	while IFS=$'\t' read -r control_id control_key default_value; do
		if [ -n "$control_id" ]; then
			"$dialog" "$window_uuid" "$control_id" "$default_value"
		fi
	done < "$defaults_path"
}

# Escape one line for embedding in a JSON string literal.
json_escape()
{
	printf '%s' "$1" | /usr/bin/sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/$(printf '\t')/\\\\t/g" \
		-e 's/[[:cntrl:]]//g'
}

# Where a window keeps the exact item list it built each dropdown from. Reading the
# text back from here rather than re-reading the recents file means a click resolves
# against the list the user is actually looking at, even if the file changed since.
combo_state_dir()
{
	printf '%s' "${TMPDIR:-/tmp}/com.abracode.Find.$window_uuid"
}

combo_item_id_base()
{
	echo $(( COMBO_ITEM_ID_BASE + $1 * COMBO_ITEM_ID_STRIDE ))
}

# Fill one combo's dropdown. The Menu itself is declared in the JSON - so the button
# renders whether or not this runs - and each item is appended as a Button whose id
# encodes the combo and the item's position. COMBO_ITEM_ID_STRIDE caps a dropdown at
# 100 items, which is well past useful.
#
# The item list is also written to a per-window snapshot, so find.combo.pick resolves
# a position back to text against the list the user is actually looking at.
set_combo_picker_options()
{
	local field_id="$1"
	shift

	local menu_id=$(( field_id + COMBO_PICKER_OFFSET ))
	local state_path="$(combo_state_dir)/combo.$field_id"
	local base=$(combo_item_id_base "$field_id")
	local index=0
	local seen_items=""
	local list_path
	local one_item
	local escaped

	/bin/mkdir -p "$(combo_state_dir)"
	: > "$state_path"

	for list_path in "$@"; do
		if [ ! -f "$list_path" ]; then
			continue
		fi
		while IFS= read -r one_item || [ -n "$one_item" ]; do
			if [ -z "$one_item" ]; then
				continue
			fi
			if [ "$index" -ge "$COMBO_ITEM_ID_STRIDE" ]; then
				break
			fi
			# a duplicate would give the user the same line twice
			if printf '%s\n' "$seen_items" | /usr/bin/grep -Fxq -- "$one_item"; then
				continue
			fi
			seen_items="$seen_items
$one_item"
			printf '%s\n' "$one_item" >> "$state_path"
			escaped=$(json_escape "$one_item")
			"$dialog" "$window_uuid" "$menu_id" omc_insert_element \
				"$(printf '{"type":"Button","id":%s,"properties":{"title":"%s","actionID":"find.combo.pick"}}' \
					"$(( base + index ))" "$escaped")" \
				children append
			index=$(( index + 1 ))
		done < "$list_path"
	done
}
