#!/bin/sh

self_dir=$(/usr/bin/dirname "$0")

app_to_sign="$1"
if test -z "$app_to_sign"; then
	echo "error: a path to app must be provided"
	exit 1
fi

echo ""
echo "errors from install_name_tool about missing LC_RPATH are ignorable (all is as expected)"
/usr/bin/install_name_tool -delete_rpath "@loader_path/../../../Frameworks" "$app_to_sign/Contents/MacOS/OMCApplet"
echo ""

app_id=$(/usr/bin/defaults read "$app_to_sign/Contents/Info.plist" CFBundleIdentifier)
if test "$?" != "0"; then
	echo "error: could not obtain bundle identifier for app at: $app_to_sign"
	exit 1
fi

/usr/bin/codesign --deep --verbose --force --options runtime --entitlements "$self_dir/OMCApplet.entitlements" --timestamp --identifier "$app_id" --sign "T9NM2ZLDTY" "$app_to_sign"
