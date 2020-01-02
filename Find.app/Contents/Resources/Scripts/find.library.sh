#!/bin/sh

dialog="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
plister="$OMC_OMC_SUPPORT_PATH/plister"
filt="$OMC_OMC_SUPPORT_PATH/filt"
pasteboard="$OMC_OMC_SUPPORT_PATH/pasteboard"
next_command="$OMC_OMC_SUPPORT_PATH/omc_next_command"

get_command_from_dialog_controls()
{
	local output_command="/usr/bin/find"
	local start_dir="$OMC_NIB_DIALOG_CONTROL_1_VALUE"
	#local config_name="$OMC_NIB_DIALOG_CONTROL_2_VALUE"
	#local output_command="$OMC_NIB_DIALOG_CONTROL_3_VALUE"
	
	local use_alphabetical_order="$OMC_NIB_DIALOG_CONTROL_111_VALUE"
	if [ "$use_alphabetical_order" = "1" ]; then
		output_command="$output_command -s"
	fi

	local pattern="$OMC_NIB_DIALOG_CONTROL_102_VALUE"
	if [ -n "$pattern" ]; then
		local pattern_choice="$OMC_NIB_DIALOG_CONTROL_101_VALUE"
		local pattern_case_sensitive="$OMC_NIB_DIALOG_CONTROL_103_VALUE"
		if [ "$pattern_choice" = "-iname" ]; then
			if [ "$pattern_case_sensitive" = "1" ]; then
				pattern_choice="-name"
			fi
		elif [ "$pattern_choice" = "-ipath" ]; then
			local pattern_regex="$OMC_NIB_DIALOG_CONTROL_104_VALUE"
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

		output_command="$output_command '$start_dir' $pattern_choice '$pattern'"
	else
		output_command="$output_command '$start_dir'"
	fi


	local file_type="$OMC_NIB_DIALOG_CONTROL_201_VALUE"
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
	local extended_attributes="$OMC_NIB_DIALOG_CONTROL_202_VALUE"
	if [ "$extended_attributes" = "Ignore" ]; then
		primary_xattr=""
	elif [ "$extended_attributes" = "Any" ]; then
		primary_xattr="-xattr"
	elif [ "$extended_attributes" = "None" ]; then
		primary_xattr="-not -xattr"
	elif [ -n "$extended_attributes" ]; then
		output_command="$output_command -xattrname '$extended_attributes'"
	fi

	if [ -n "$primary_xattr" ]; then
		output_command="$output_command $primary_xattr"
	fi

	local size_choice="$OMC_NIB_DIALOG_CONTROL_301_VALUE"
	local size_number="$OMC_NIB_DIALOG_CONTROL_302_VALUE"
	if [ -n "$size_choice" ] && [ -n "$size_number" ]; then
		if [ "$size_choice" = "=" ]; then
			size_choice=""
		fi
		local size_scale="$OMC_NIB_DIALOG_CONTROL_303_VALUE"
		output_command="$output_command -size $size_choice$size_number$size_scale"
	fi

	local size_empy_test="$OMC_NIB_DIALOG_CONTROL_304_VALUE"
	if [ -n "$size_empy_test" ]; then
		output_command="$output_command $size_empy_test"
	fi

	local permissions_choice="$OMC_NIB_DIALOG_CONTROL_401_VALUE"
	if [ -n "$permissions_choice" ]; then
		if [ "$permissions_choice" = "=" ]; then
			permissions_choice=""
		fi
		
		perm_user=""
		local permissions_user_read="$OMC_NIB_DIALOG_CONTROL_411_VALUE"
		local permissions_user_write="$OMC_NIB_DIALOG_CONTROL_412_VALUE"
		local permissions_user_exec="$OMC_NIB_DIALOG_CONTROL_413_VALUE"
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
		local permissions_group_read="$OMC_NIB_DIALOG_CONTROL_421_VALUE"
		local permissions_group_write="$OMC_NIB_DIALOG_CONTROL_422_VALUE"
		local permissions_group_exec="$OMC_NIB_DIALOG_CONTROL_423_VALUE"
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
		local permissions_other_read="$OMC_NIB_DIALOG_CONTROL_431_VALUE"
		local permissions_other_write="$OMC_NIB_DIALOG_CONTROL_432_VALUE"
		local permissions_other_exec="$OMC_NIB_DIALOG_CONTROL_433_VALUE"
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
			output_command="$output_command -perm '$permissions_choice$perm_combined'"
		fi
	fi

	local time_access_choice="$OMC_NIB_DIALOG_CONTROL_511_VALUE"
	local time_access_number="$OMC_NIB_DIALOG_CONTROL_512_VALUE"
	if [ -n "$time_access_choice" ] && [ -n "$time_access_number" ]; then
		local time_access_unit="$OMC_NIB_DIALOG_CONTROL_513_VALUE"
		output_command="$output_command -atime $time_access_choice$time_access_number$time_access_unit"
	fi
	
	local time_creation_choice="$OMC_NIB_DIALOG_CONTROL_521_VALUE"
	local time_creation_number="$OMC_NIB_DIALOG_CONTROL_522_VALUE"
	if [ -n "$time_creation_choice" ] && [ -n "$time_creation_number" ]; then
		local time_creation_unit="$OMC_NIB_DIALOG_CONTROL_523_VALUE"
		output_command="$output_command -Btime $time_creation_choice$time_creation_number$time_creation_unit"
	fi

	local time_modification_choice="$OMC_NIB_DIALOG_CONTROL_531_VALUE"
	local time_modification_number="$OMC_NIB_DIALOG_CONTROL_532_VALUE"
	if [ -n "$time_modification_choice" ] && [ -n "$time_modification_number" ]; then
		local time_modification_unit="$OMC_NIB_DIALOG_CONTROL_533_VALUE"
		output_command="$output_command -mtime $time_modification_choice$time_modification_number$time_modification_unit"
	fi

	local time_status_choice="$OMC_NIB_DIALOG_CONTROL_541_VALUE"
	local time_status_number="$OMC_NIB_DIALOG_CONTROL_542_VALUE"
	if [ -n "$time_status_choice" ] && [ -n "$time_status_number" ]; then
		local time_status_unit="$OMC_NIB_DIALOG_CONTROL_543_VALUE"
		output_command="$output_command -ctime $time_status_choice$time_status_number$time_status_unit"
	fi

	local depth_min="$OMC_NIB_DIALOG_CONTROL_611_VALUE"
	if [ -n "$depth_min" ]; then
		output_command="$output_command -mindepth $depth_min"
	fi
	
	local depth_max="$OMC_NIB_DIALOG_CONTROL_612_VALUE"
	if [ -n "$depth_max" ]; then
		output_command="$output_command -maxdepth $depth_max"
	fi
	
	local action_choice="$OMC_NIB_DIALOG_CONTROL_801_VALUE"
	local action_also_print="$OMC_NIB_DIALOG_CONTROL_803_VALUE"
	if [ "$action_also_print" = "1" ] && [ "$action_choice" != "-print" ] && [ "$action_choice" != "-print0" ]; then
		output_command="$output_command -print"
	fi

	if [ "$action_choice" = "-exec" -o  "$action_choice" = "-execdir" ]; then
		local action_exec_tool="$OMC_NIB_DIALOG_CONTROL_802_VALUE"
		if [ -n "$action_exec_tool" ]; then
			output_command="$output_command $action_choice $action_exec_tool ';'"
		fi
	elif [ -n "$action_choice" ]; then
		output_command="$output_command $action_choice"
	fi
	
	local output_choice="$OMC_NIB_DIALOG_CONTROL_901_VALUE"
	local output_script="$OMC_NIB_DIALOG_CONTROL_902_VALUE"
	if [ -n "$output_choice" ] && [ -n "$output_script" ]; then
		if [ "$output_choice" = ">" ]; then
			output_command="$output_command > \"$output_script\""
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
	local pattern_choice="$OMC_NIB_DIALOG_CONTROL_101_VALUE"
	if [ "$pattern_choice" = "-ipath" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 104 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 104 omc_disable
	fi
}

update_action_controls()
{
	local action_choice="$OMC_NIB_DIALOG_CONTROL_801_VALUE"
	if [ "$action_choice" = "-print" -o "$action_choice" = "-print0" -o "$action_choice" = "-ls" -o "$action_choice" = "-delete" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 802 omc_disable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 802 omc_enable
	fi
	
	if [ "$action_choice" = "-print" -o "$action_choice" = "-print0" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 803 omc_disable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 803 omc_enable
	fi	
}

update_output_controls()
{
	local output_choice="$OMC_NIB_DIALOG_CONTROL_901_VALUE"
	if [ -n "$output_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 902 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 902 omc_disable
	fi
}

update_size_controls()
{
	local size_choice="$OMC_NIB_DIALOG_CONTROL_301_VALUE"
	if [ -n "$size_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 302 omc_enable
		"$dialog" "$OMC_NIB_DLG_GUID" 303 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 302 omc_disable
		"$dialog" "$OMC_NIB_DLG_GUID" 303 omc_disable
	fi
}

update_permissions_controls()
{
	local permissions_choice="$OMC_NIB_DIALOG_CONTROL_401_VALUE"
	if [ -n "$permissions_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 402 omc_enable
	else
	 	"$dialog" "$OMC_NIB_DLG_GUID" 402 omc_disable
	fi
}


update_time_controls()
{
	local time_access_choice="$OMC_NIB_DIALOG_CONTROL_511_VALUE"
	if [ -n "$time_access_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 512 omc_enable
		"$dialog" "$OMC_NIB_DLG_GUID" 513 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 512 omc_disable
		"$dialog" "$OMC_NIB_DLG_GUID" 513 omc_disable
	fi
	
	local time_creation_choice="$OMC_NIB_DIALOG_CONTROL_521_VALUE"
	if [ -n "$time_creation_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 522 omc_enable
		"$dialog" "$OMC_NIB_DLG_GUID" 523 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 522 omc_disable
		"$dialog" "$OMC_NIB_DLG_GUID" 523 omc_disable
	fi

	local time_modification_choice="$OMC_NIB_DIALOG_CONTROL_531_VALUE"
	if [ -n "$time_modification_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 532 omc_enable
		"$dialog" "$OMC_NIB_DLG_GUID" 533 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 532 omc_disable
		"$dialog" "$OMC_NIB_DLG_GUID" 533 omc_disable
	fi

	local time_status_choice="$OMC_NIB_DIALOG_CONTROL_541_VALUE"
	if [ -n "$time_status_choice" ]; then
		"$dialog" "$OMC_NIB_DLG_GUID" 542 omc_enable
		"$dialog" "$OMC_NIB_DLG_GUID" 543 omc_enable
	else
		"$dialog" "$OMC_NIB_DLG_GUID" 542 omc_disable
		"$dialog" "$OMC_NIB_DLG_GUID" 543 omc_disable
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

	# existence of this dir is ensured in dialog init handler
	local app_support_dir="$HOME/Library/Application Support/com.abracode.Find"
	local recent_list_path="$app_support_dir/$list_name"

	local recent_items_array
	# the new item might be a duplicate of an existing item in array
	recent_items_array=( "$recent_item" )
	while IFS=$'\n' read -r one_item; do
		if [ "$recent_item" != "$one_item" ]; then
			recent_items_array+=("$one_item")
		fi
	done < "$recent_list_path"
	
	local array_count=${#recent_items_array[@]}
	if [ "$array_count" -gt "$max_count" ]; then
		array_count="$max_count"
	fi
	
	/bin/rm "$recent_list_path"

	# in bash array index starts with 0 but in zsh it starts with 1!
	# in macOS 10.15 Catalina zsh is the default shell but it does not change /bin/sh
	# which is still bash
	local line_index=0
	while [ "$line_index" -lt "$array_count" ]; do
		echo "${recent_items_array[$line_index]}" >> "$recent_list_path"
		let "line_index++"
	done
}

