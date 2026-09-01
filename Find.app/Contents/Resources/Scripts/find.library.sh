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
# The Content tab. Its 7xx block was added after 1xx-6xx were fixed, so the number
# does not track the tab's position the way the earlier blocks do - the tab sits
# second, beside Name. Renumbering the others would break every saved config.
CONTENT_ID=701
CONTENT_CASE_SENSITIVE_ID=702
CONTENT_USE_REGEX_ID=703
CONTENT_SKIP_BINARY_ID=704
ACTION_KIND_ID=801
ACTION_TOOL_ID=802
ALSO_PRINT_ID=803
OUTPUT_KIND_ID=901
OUTPUT_TARGET_ID=902

# A combo box has no ActionUI equivalent, so each one is a TextField carrying the
# legacy id plus a companion dropdown at COMBO_PICKER_OFFSET + that id. The dropdown
# is a Menu rather than a Picker: a menu-style Picker reserves a fixed leading inset
# for its hidden title, which leaves the chevron visibly off-center in a button this
# narrow. A Menu draws only its label, so the glyph centers.
#
# The JSON declares the Menu itself, and set_combo_picker_options appends one Button
# per item. Each item Button carries an id encoding which combo it belongs to and its
# position in the list, and find.combo.pick resolves that back to the item text
# through the snapshot the last rebuild wrote.
COMBO_PICKER_OFFSET=1000
COMBO_ITEM_ID_BASE=100000
COMBO_ITEM_ID_STRIDE=100
COMBO_FIELD_IDS="$LOCATION_ID $CONFIG_ID $PATTERN_ID $CONTENT_ID $XATTR_ID $ACTION_TOOL_ID $OUTPUT_TARGET_ID"

# ActionUI refuses a Picker option whose tag is empty, so every menu item that
# meant "no choice" in the nib carries this sentinel tag instead.
NO_CHOICE_TAG="none"
SENTINEL_PICKER_IDS="$FILE_TYPE_ID $SIZE_COMPARE_ID $EMPTINESS_ID $PERMISSIONS_COMPARE_ID 511 521 531 541 $OUTPUT_KIND_ID"

# ActionUI Toggles carry a Bool, so they arrive as "true"/"false" where the nib
# checkboxes arrived as "1"/"0".
TOGGLE_IDS="$CASE_SENSITIVE_ID $USE_REGEX_ID $ALPHABETICAL_ID $STAY_ON_VOLUME_ID $CONTENT_CASE_SENSITIVE_ID $CONTENT_USE_REGEX_ID $CONTENT_SKIP_BINARY_ID 411 412 413 421 422 423 431 432 433 $ALSO_PRINT_ID"

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
#
# Every value that reaches the command text as DATA goes through here - paths,
# patterns, names, and the number fields too. "Number" is what the prompt asks for,
# not what the control enforces: 611 and 612 are plain text fields like any other,
# so "2; rm -rf ~ #" is as typeable there as anywhere, and a saved config can put it
# there with nobody typing at all. Values that are not data are handled two other
# ways - see reject_unknown_picker_tags for the Pickers, and the comments at 802 and
# 902 for the two fields that deliberately ask the user for a command.
#
# Written as a shell loop rather than the obvious sed pipeline, because that pipeline
# failed OPEN. sed aborts on an illegal byte sequence in a UTF-8 locale having already
# emitted a partial stream, and inside $( ) that status is discarded twice over, so a
# bad byte in the content pattern silently produced "" - and "grep -e ''" matches
# every file, which with Delete selected is the unfiltered search this file goes out
# of its way to prevent a hundred lines below. $( ) also strips trailing newlines,
# which would quietly retarget a search at a folder whose name ends in one. The loop
# has neither failure mode, and forks nothing.
shell_quote()
{
	local _rest="$1"
	local _done=""
	while :; do
		case "$_rest" in
			*"'"*)
				_done="$_done${_rest%%\'*}'\\''"
				_rest="${_rest#*\'}"
				;;
			*)
				break
				;;
		esac
	done
	printf "'%s'" "$_done$_rest"
}

# ActionUI stores a Picker's value as whatever string it is handed: Picker declares
# parseStringValue = nil and valueType = String.self, so nothing ever checks a value
# against the option tags in Find.json. find.load.config.sh replays a config file
# into "$dialog" <id> <value> without validating either field, and a config is a
# plain TSV in an Application Support directory this app is not sandboxed away from,
# listed by name in the Config dropdown. A Picker is therefore no more trustworthy
# than a text field, and its value reaches the same eval.
#
# These five cannot be handled with shell_quote. Their tags are find primaries that
# are two words ("-not -type", "-not -empty") or a redirection operator, and all of
# them depend on the shell splitting them - quoting would break the feature. An
# allow-list is the fix.
#
# An unrecognized value falls back to the control's documented default rather than
# being passed along. For the three with a "no choice" state that means the clause is
# simply not emitted, so a corrupt or hostile config narrows a search rather than
# widening or redirecting it.
reject_unknown_picker_tags()
{
	case "$OMC_ACTIONUI_VIEW_101_VALUE" in
		-iname|-ipath) ;;
		*) OMC_ACTIONUI_VIEW_101_VALUE="-iname" ;;
	esac
	case "$OMC_ACTIONUI_VIEW_201_VALUE" in
		""|f|d|l|"!f"|"!d"|"!l") ;;
		*) OMC_ACTIONUI_VIEW_201_VALUE="" ;;
	esac
	case "$OMC_ACTIONUI_VIEW_304_VALUE" in
		""|-empty|"-not -empty") ;;
		*) OMC_ACTIONUI_VIEW_304_VALUE="" ;;
	esac
	case "$OMC_ACTIONUI_VIEW_801_VALUE" in
		-print|-print0|-ls|-exec|-execdir|-delete) ;;
		*) OMC_ACTIONUI_VIEW_801_VALUE="-print" ;;
	esac
	case "$OMC_ACTIONUI_VIEW_901_VALUE" in
		""|"|"|">"|"?") ;;
		*) OMC_ACTIONUI_VIEW_901_VALUE="" ;;
	esac
}

# After normalize_actionui_controls, so the "none" sentinel has already become "".
reject_unknown_picker_tags

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
		output_command="$output_command -size $(shell_quote "$size_choice$size_number$size_scale")"
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
		output_command="$output_command -atime $(shell_quote "$time_access_choice$time_access_number$time_access_unit")"
	fi
	
	local time_creation_choice="$OMC_ACTIONUI_VIEW_521_VALUE"
	local time_creation_number="$OMC_ACTIONUI_VIEW_522_VALUE"
	if [ -n "$time_creation_choice" ] && [ -n "$time_creation_number" ]; then
		local time_creation_unit="$OMC_ACTIONUI_VIEW_523_VALUE"
		output_command="$output_command -Btime $(shell_quote "$time_creation_choice$time_creation_number$time_creation_unit")"
	fi

	local time_modification_choice="$OMC_ACTIONUI_VIEW_531_VALUE"
	local time_modification_number="$OMC_ACTIONUI_VIEW_532_VALUE"
	if [ -n "$time_modification_choice" ] && [ -n "$time_modification_number" ]; then
		local time_modification_unit="$OMC_ACTIONUI_VIEW_533_VALUE"
		output_command="$output_command -mtime $(shell_quote "$time_modification_choice$time_modification_number$time_modification_unit")"
	fi

	local time_status_choice="$OMC_ACTIONUI_VIEW_541_VALUE"
	local time_status_number="$OMC_ACTIONUI_VIEW_542_VALUE"
	if [ -n "$time_status_choice" ] && [ -n "$time_status_number" ]; then
		local time_status_unit="$OMC_ACTIONUI_VIEW_543_VALUE"
		output_command="$output_command -ctime $(shell_quote "$time_status_choice$time_status_number$time_status_unit")"
	fi

	# Trimmed because quoting made padding fatal where word splitting used to hide it:
	# "-maxdepth '1 '" is an illegal value to find, where "-maxdepth 1 " split back to
	# "1". A pasted number routinely carries a space.
	local depth_min="$OMC_ACTIONUI_VIEW_611_VALUE"
	depth_min="${depth_min#"${depth_min%%[![:space:]]*}"}"
	depth_min="${depth_min%"${depth_min##*[![:space:]]}"}"
	if [ -n "$depth_min" ]; then
		output_command="$output_command -mindepth $(shell_quote "$depth_min")"
	fi
	
	local depth_max="$OMC_ACTIONUI_VIEW_612_VALUE"
	depth_max="${depth_max#"${depth_max%%[![:space:]]*}"}"
	depth_max="${depth_max%"${depth_max##*[![:space:]]}"}"
	if [ -n "$depth_max" ]; then
		output_command="$output_command -maxdepth $(shell_quote "$depth_max")"
	fi
	
	# The content match. -exec is used here as a CONDITION rather than an action: find
	# takes the command's exit status as the test result, so this filters exactly the
	# way -size or -type does and still composes with whatever action follows - which
	# is what lets "delete every *.log containing X" stay one find command.
	#
	# It is emitted after every other test on purpose. find evaluates left to right and
	# short-circuits, so the grep only ever runs on files that already passed the cheap
	# predicates. Measured on 3000 files: 0.06s here against 3.6s if it ran first.
	local content_pattern="$OMC_ACTIONUI_VIEW_701_VALUE"
	# grep reads every LINE of -e as a pattern of its own, so a blank line anywhere in
	# a multi-line value is an empty alternative that matches every file - "find the
	# files containing X" silently becomes "list everything".
	#
	# Only when there is more than one line. A single line has no alternatives, so it
	# is exactly the pattern the user meant even when it is nothing but spaces, and
	# stripping it would break a deliberate search for whitespace. Blank covers spaces,
	# tabs and a lone CR, not just an empty line: text pasted from a browser or a
	# Windows-authored file is CRLF, which makes a bare /^$/ miss the likeliest paste
	# there is.
	local content_newline='
'
	local content_stripped
	case "$content_pattern" in
		*"$content_newline"*)
			content_stripped=$(printf '%s' "$content_pattern" \
				| /usr/bin/sed '/^[[:space:]]*$/d')
			# Only on success. sed exits non-zero on an illegal byte sequence having
			# emitted a truncated stream, and taking that would turn a filtered search
			# into an unfiltered one - which with Delete selected is not a small thing.
			if [ $? -eq 0 ]; then
				content_pattern="$content_stripped"
			fi
			;;
	esac
	local content_emitted=0
	if [ -n "$content_pattern" ]; then
		content_emitted=1
		local content_grep="/usr/bin/grep -q"
		# The Name tab matches case-insensitively unless asked otherwise, and the
		# content match follows it rather than inventing a second convention.
		if [ "$OMC_ACTIONUI_VIEW_702_VALUE" != "1" ]; then
			content_grep="$content_grep -i"
		fi
		# Always one of -F or -E, never bare grep: plain grep is BRE, where "." and
		# "*" are still metacharacters, so an unchecked "Use regex pattern" box would
		# be lying about a pattern like "a.c". -F is genuinely literal, and -E is the
		# extended flavor, the same one find -E gives -regex.
		if [ "$OMC_ACTIONUI_VIEW_703_VALUE" = "1" ]; then
			content_grep="$content_grep -E"
		else
			content_grep="$content_grep -F"
		fi
		if [ "$OMC_ACTIONUI_VIEW_704_VALUE" = "1" ]; then
			content_grep="$content_grep -I"
		fi
		# -type f is not a nicety. grep blocks forever in read() on a FIFO, and macOS
		# puts real ones in a home directory - Realm keeps three under
		# ~/Library/Containers here - so without this, "search my home folder for some
		# text" hangs with no error and no way to see why. Character devices with no
		# EOF hang the same way. -I cannot help: nothing has been read yet. It also
		# saves one grep fork and one "Is a directory" line per directory in the tree.
		#
		# Skipped when the file type picker already said regular files, purely to keep
		# the preview free of a duplicate. Three of that picker's other choices are
		# contradictory with it and each correctly finds nothing: "Directories" and
		# "Not regular files" because neither names something with contents to match,
		# and "Symbolic links" for a subtler reason - grep would happily read through a
		# link to its target, but following links is exactly what reopens the hang this
		# guard exists for, since a link can point at a FIFO.
		if [ "$OMC_ACTIONUI_VIEW_201_VALUE" != "f" ]; then
			output_command="$output_command -type f"
		fi
		# -e, so a pattern that begins with "-" is read as a pattern and not an option.
		output_command="$output_command -exec $content_grep -e $(shell_quote "$content_pattern") {} ';'"
	fi

	local action_choice="$OMC_ACTIONUI_VIEW_801_VALUE"
	local action_also_print="$OMC_ACTIONUI_VIEW_803_VALUE"
	local action_emitted=0
	if [ "$action_also_print" = "1" ] && [ "$action_choice" != "-print" ] && [ "$action_choice" != "-print0" ]; then
		output_command="$output_command -print"
		action_emitted=1
	fi

	# Not shell_quoted, and that is the point: this field asks for a tool invocation
	# with its arguments, so the shell has to see the words as words. See shell_quote.
	if [ "$action_choice" = "-exec" -o  "$action_choice" = "-execdir" ]; then
		local action_exec_tool="$OMC_ACTIONUI_VIEW_802_VALUE"
		if [ -n "$action_exec_tool" ]; then
			output_command="$output_command $action_choice $action_exec_tool ';'"
			action_emitted=1
		fi
	elif [ -n "$action_choice" ]; then
		output_command="$output_command $action_choice"
		action_emitted=1
	fi

	# find supplies an implicit -print only when the expression contains no -exec, -ls
	# or -print of its own. The content test is an -exec, so it satisfies that rule and
	# cancels the implicit print. Without this, choosing "Execute tool", leaving the
	# tool field empty and unticking "Also print" turns a content search from "lists
	# every match" into "prints nothing at all", with nothing on screen to explain it.
	if [ "$content_emitted" = "1" ] && [ "$action_emitted" = "0" ]; then
		output_command="$output_command -print"
	fi
	
	local output_choice="$OMC_ACTIONUI_VIEW_901_VALUE"
	local output_script="$OMC_ACTIONUI_VIEW_902_VALUE"
	# ">" takes a save path, which is data and is quoted. The other two branches take
	# a command to pipe into or to append verbatim, so they stay raw. See shell_quote.
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
	
	# Written beside the list and moved into place, rather than truncating the list and
	# refilling it: the dropdowns are now rebuilt from these files while the window is
	# open, and a refresh that read one mid-rewrite would offer a truncated list, or
	# none at all.
	local recent_list_new="$recent_list_path.new.$$"
	: > "$recent_list_new"

	# in bash array index starts with 0 but in zsh it starts with 1!
	# in macOS 10.15 Catalina zsh is the default shell but it does not change /bin/sh
	# which is still bash
	local line_index=0
	while [ "$line_index" -lt "$array_count" ]; do
		echo "${recent_items_array[$line_index]}" >> "$recent_list_new"
		let "line_index++"
	done

	/bin/mv "$recent_list_new" "$recent_list_path"
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

# Set to "yes" by find.init, the one handler that runs before any dropdown holds an
# item. Every other caller leaves it empty, and on those paths a missing snapshot
# cannot be read as "the menu is empty" - see set_combo_picker_options.
combo_menus_are_fresh=""

# How old an unstamped lock has to be before a waiter treats it as abandoned. Only the
# instant between creating a lock and stamping it is unstamped, so this is a backstop
# for a handler killed inside that window, not the usual test - which is whether the
# process that stamped it still exists.
COMBO_LOCK_STALE_MINUTES=5

# Which process holds this lock, if it says.
combo_lock_owner() # <lock-dir> -> pid, or nothing
{
	local owner
	for owner in "$1"/owner.*; do
		if [ -d "$owner" ]; then
			printf '%s' "${owner##*/owner.}"
			return 0
		fi
	done
	return 0
}

# Hold the lock for one combo's rebuild. A directory, because mkdir either creates it
# or fails, atomically, where a lock file written with > does neither.
combo_lock_acquire() # <lock-dir> -> 0 held, 1 gave up
{
	local lock_path="$1"
	local waited=0
	local owner_pid
	while ! /bin/mkdir "$lock_path" 2>/dev/null; do
		# Five seconds, then give up and leave the dropdown to the handler that has the
		# lock. A refresh dropped this way costs nothing that is not recoverable: the
		# terms it would have offered are already on disk, and the handler ahead of it
		# is reading the same files. The caller ignores the status for that reason.
		if [ "$waited" -ge 50 ]; then
			return 1
		fi
		# A handler killed while holding the lock would otherwise wedge every later
		# refresh for the life of the window - and the dropdown it left behind is
		# exactly the one that needs rebuilding. So a lock whose holder is gone is
		# taken away from it.
		#
		# Deciding that and acting on it has to be one step. Two waiters that both
		# decide the same lock is abandoned both remove it, and the second removes the
		# lock the first has already retaken - putting two rebuilds in the section at
		# once, which is the one thing this function exists to prevent. The breaker
		# serializes the decision, so by the time its next holder looks, a lock that
		# was just taken is stamped by a live process and no longer a candidate. An
		# orphaned breaker degrades to "nobody steals", which is a stall, not a
		# corruption.
		#
		# The test is whether the holder still exists, not how old its lock is. Age
		# says nothing useful here: the holder can be walking a whole stride of
		# removals one process at a time, and a lock's mtime keeps ageing across a
		# system sleep or a SIGSTOP while its holder makes no progress at all. Stealing
		# from a live holder is the corruption this exists to prevent; waiting out a
		# genuinely dead one only costs a dropdown that stays stale until the next
		# search.
		if /bin/mkdir "$lock_path.breaker" 2>/dev/null; then
			owner_pid="$(combo_lock_owner "$lock_path")"
			if [ -z "$owner_pid" ]; then
				if [ -n "$(/usr/bin/find "$lock_path" -maxdepth 0 -mmin +"$COMBO_LOCK_STALE_MINUTES" 2>/dev/null)" ]; then
					/bin/rm -rf "$lock_path"
				fi
			elif ! /bin/kill -0 "$owner_pid" 2>/dev/null; then
				/bin/rm -rf "$lock_path"
			fi
			/bin/rmdir "$lock_path.breaker" 2>/dev/null
		fi
		/bin/sleep 0.1
		waited=$(( waited + 1 ))
	done
	/bin/mkdir "$lock_path/owner.$$" 2>/dev/null
	return 0
}

# Give the lock up, but only if it is still ours. A handler whose lock was taken from
# it - because it looked dead, or because its stamp never landed - must not remove the
# one that replaced it, or a third rebuild walks in on the handler that took it.
combo_lock_release() # <lock-dir>
{
	if [ -d "$1/owner.$$" ]; then
		/bin/rm -rf "$1"
	fi
}

# Fill one combo's dropdown. The Menu itself is declared in the JSON - so the button
# renders whether or not this runs - and each item is appended as a Button whose id
# encodes the combo and the item's position. COMBO_ITEM_ID_STRIDE caps a dropdown at
# 100 items, which is well past useful.
#
# The item list is also written to a per-window snapshot, so find.combo.pick resolves
# a position back to text against the list the user is actually looking at.
#
# Safe to call again on a window that is already open, which is what lets a search
# put its own terms in the dropdowns without the user closing and reopening. The new
# list is built first and compared with the snapshot: an unchanged dropdown is left
# alone entirely, and a changed one has its old items removed before the new ones go
# in. Removing them is not optional - the ids come from the position, and ActionUI
# refuses an insert whose id is already live, so appending over the old items would
# quietly leave the stale list on screen.
set_combo_picker_options()
{
	local field_id="$1"
	shift

	local menu_id=$(( field_id + COMBO_PICKER_OFFSET ))
	local state_dir="$(combo_state_dir)"
	local state_path="$state_dir/combo.$field_id"
	# Built alongside the snapshot rather than over it: until the dropdown has really
	# been rebuilt, the snapshot has to keep describing what is on screen, because
	# find.combo.pick is what resolves a click through it.
	# One per process: two handlers refreshing the same combo at once - a second Find
	# pressed while the first is still going - would otherwise interleave their appends
	# into a list that is neither.
	local pending_path="$state_path.pending.$$"
	# Present only while the menu and the snapshot are allowed to disagree. A handler
	# killed mid-rebuild leaves it behind, and the next call takes that as "rebuild
	# whatever the comparison says" - otherwise a half-inserted dropdown compares equal
	# to its own snapshot for ever and is never repaired.
	local dirty_path="$state_path.rebuilding"
	local lock_path="$state_path.lock"
	local base=$(combo_item_id_base "$field_id")
	local index=0
	local seen_items=""
	local list_path
	local one_item
	local escaped

	/bin/mkdir -p "$state_dir"
	: > "$pending_path"

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
			printf '%s\n' "$one_item" >> "$pending_path"
			index=$(( index + 1 ))
		done < "$list_path"
	done

	# Everything from the comparison to the last insert is one rebuild, and two of them
	# interleaved can leave an item id live whose snapshot line says something else
	# entirely - which is the one outcome the whole ordering exists to prevent.
	if ! combo_lock_acquire "$lock_path"; then
		/bin/rm -f "$pending_path"
		return 1
	fi

	if [ ! -f "$dirty_path" ] && [ -f "$state_path" ] && /usr/bin/cmp -s "$state_path" "$pending_path"; then
		/bin/rm -f "$pending_path"
		combo_lock_release "$lock_path"
		return 0
	fi

	: > "$dirty_path"

	# The snapshot is also the record of what the menu is holding, so its line count
	# is how many item ids are live. Nothing else knows: the ids are derived from a
	# position, not stored, and this handler may not be the one that inserted them.
	local old_count=0
	if [ -f "$state_path" ]; then
		old_count=$(/usr/bin/awk 'END { print NR }' "$state_path")
	elif [ "$combo_menus_are_fresh" != "yes" ]; then
		# No snapshot, on a window that already has its dropdowns: the state directory
		# lives in TMPDIR, which the system sweeps out from under a window left open
		# for days. Assume every id the combo can mint is live rather than none of
		# them - an insert whose id is already taken is refused, and refused silently,
		# which would leave the old list on screen under a snapshot describing the new
		# one. Removing an id that is not live costs a no-op.
		old_count="$COMBO_ITEM_ID_STRIDE"
	fi
	# Same guard the insert loop carries, and it matters more here: an id past the
	# stride belongs to the next combo, and removing one would take a live item out of
	# a dropdown this call has no business touching. Fields 1 and 2 are the only
	# adjacent pair in the id map, so that is Location reaching into Config.
	if [ "$old_count" -gt "$COMBO_ITEM_ID_STRIDE" ]; then
		old_count="$COMBO_ITEM_ID_STRIDE"
	fi
	local old_index=0
	while [ "$old_index" -lt "$old_count" ]; do
		"$dialog" "$window_uuid" "$(( base + old_index ))" omc_remove_element
		old_index=$(( old_index + 1 ))
	done

	/bin/mv "$pending_path" "$state_path"

	# Read back from the snapshot, not from the pending file: if the mv failed, the
	# snapshot still describes the old list and re-inserting that leaves menu and
	# snapshot agreeing, which is what find.combo.pick needs.
	index=0
	while IFS= read -r one_item || [ -n "$one_item" ]; do
		if [ -z "$one_item" ]; then
			continue
		fi
		# The build loop above caps the list, so this can only bite on a snapshot from
		# somewhere else - but an item minted past the stride lands in the next combo's
		# id range, and a click on it would resolve against the wrong field entirely.
		if [ "$index" -ge "$COMBO_ITEM_ID_STRIDE" ]; then
			break
		fi
		escaped=$(json_escape "$one_item")
		"$dialog" "$window_uuid" "$menu_id" omc_insert_element \
			"$(printf '{"type":"Button","id":%s,"properties":{"title":"%s","actionID":"find.combo.pick"}}' \
				"$(( base + index ))" "$escaped")" \
			children append
		index=$(( index + 1 ))
	done < "$state_path"

	/bin/rm -f "$dirty_path"
	# Not the last statement on purpose. The release is a no-op when this handler's
	# lock was taken from it, and that is not the same answer as the "gave up without
	# touching anything" that return 1 means above - this rebuild happened.
	combo_lock_release "$lock_path"
	return 0
}

# Fill every combo's dropdown from the list behind it. find.init builds them here
# when the window opens, and find.run comes back through the same function after
# recording what was just searched for - each dropdown that did not change is left
# untouched, so the second call costs nothing the user can see.
set_all_combo_picker_options()
{
	set_combo_picker_options "$LOCATION_ID" "$app_support_dir/recent_locations"
	set_combo_picker_options "$PATTERN_ID" "$app_support_dir/recent_patterns"
	set_combo_picker_options "$CONTENT_ID" "$app_support_dir/recent_content_patterns"
	set_combo_picker_options "$ACTION_TOOL_ID" "$app_support_dir/recent_exec_scripts"
	set_combo_picker_options "$OUTPUT_TARGET_ID" "$app_support_dir/recent_output_scripts"

	# Configs are listed from the directory rather than a recents file. Skipped rather
	# than attempted if the temporary file cannot be made: an unreadable list is an
	# empty list, and an empty list here would take every config out of the dropdown.
	local configs_list
	configs_list=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/find.configs.XXXXXX")
	if [ -n "$configs_list" ]; then
		# The listing has to have worked, for the same reason: an ls that failed writes
		# nothing, and refreshing from nothing would take every config out of the menu.
		# A directory that does not exist yet is not a failure - there are no configs
		# to offer, and an empty dropdown is the right answer.
		if /bin/ls "$configs_dir" > "$configs_list" 2>/dev/null || [ ! -d "$configs_dir" ]; then
			set_combo_picker_options "$CONFIG_ID" "$configs_list"
		fi
		/bin/rm -f "$configs_list"
	fi

	# The extended attributes combo keeps its shipped list and appends the recents to it.
	set_combo_picker_options "$XATTR_ID" \
		"$extended_attributes_path" \
		"$app_support_dir/recent_extended_attributes"
}
