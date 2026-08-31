#!/bin/sh
# Handles a folder dropped on the "Find In:" field. The nib's OMCComboBox accepted
# drops natively; an ActionUI TextField needs an onDropActionID to do the same.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/find.library.sh"

# ActionUI delivers {"items":["/path", ...],"location":{...}}. Items are filesystem
# paths, not file:// URLs - DropHelper resolves a dropped URL with URL.path.
#
# Cut to just past the opening bracket of "items" and look at what follows. Testing
# for the quote first is what distinguishes a real item from an empty array: without
# it the extraction below runs on past the bracket and returns a piece of "location".
array_head=$(printf '%s' "$OMC_ACTIONUI_TRIGGER_CONTEXT" | \
	/usr/bin/sed -e 's/^.*"items"[^[]*\[//' -e 's/^[[:space:]]*//')

dropped_path=""
case "$array_head" in
	'"'*)
		# The first element runs to the next quote. BSD sed has no \| alternation, so
		# this cannot track backslash escaping: a path containing a literal double
		# quote is not handled.
		dropped_path=$(printf '%s' "$array_head" | /usr/bin/sed -e 's/^"//' -e 's/".*$//')
		# undo the JSON string escaping the context arrived with
		dropped_path=$(printf '%s' "$dropped_path" | /usr/bin/sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')
		;;
esac

if [ -z "$dropped_path" ]; then
	echo "find.location.dropped: no path in drop context"
	exit 1
fi

# DropHelper offers plain text before the file-URL branch, and only that branch runs
# URL.path - so a provider carrying text hands us something that is not a path at all.
# Control 1 is interpolated into the command find.run evals, so refuse anything that
# is not an absolute path rather than passing it on.
case "$dropped_path" in
	/*)
		;;
	*)
		echo "find.location.dropped: not an absolute path: $dropped_path"
		exit 1
		;;
esac

# Dropping a file is a request to search the folder holding it.
if [ ! -d "$dropped_path" ]; then
	dropped_path=$(/usr/bin/dirname "$dropped_path")
fi

"$dialog" "$window_uuid" "$LOCATION_ID" "$dropped_path"
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "find.update.output"
