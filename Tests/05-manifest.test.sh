#!/bin/sh
# Tests/05-manifest.test.sh - how the applet is wired before any window opens.
#
# Two conversions land here. The command manifest is Command.json rather than
# Command.plist, and the menu bar is built programmatically from MainMenu.json
# rather than loaded from MainMenu.nib. Both fail silently when mis-wired: OMC
# falls back to the nib path without complaint if Info.plist still names one, and
# a menu item whose actionID matches no command is simply dead when clicked.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.find.sh"

BASE_LPROJ="$APP_RESOURCES/Base.lproj"
MENU_JSON="$BASE_LPROJ/MainMenu.json"

# Several checks below expect an empty result to mean "nothing wrong". A python
# snippet that raises writes its traceback to stderr and nothing to stdout, which
# would read as exactly that and pass vacuously. Turning a non-zero exit into a
# visible marker makes those checks fail closed instead.
run_py() {
    python3 - "$@" || echo "SNIPPET-FAILED"
}

section "the applet carries exactly one command manifest"
check "Command.json is the manifest" "yes" \
    "$([ -f "$APP_RESOURCES/Command.json" ] && echo yes || echo no)"
check_absent "and the legacy plist is gone" "$APP_RESOURCES/Command.plist"
check "and it is well-formed JSON with the root key the engine reads" "yes" \
    "$(run_py "$APP_RESOURCES" <<'PY'
import json, os, sys
doc = json.load(open(os.path.join(sys.argv[1], "Command.json")))
print("yes" if isinstance(doc.get("COMMAND_LIST"), list) and doc.get("VERSION") == 2 else "no")
PY
)"

section "every handler script is declared, and every declaration has a handler"
# Synthesis would paper over a missing declaration, so this is about the manifest
# staying honest rather than about dispatch working.
_missing_decl=$(run_py "$APP_RESOURCES" <<'PY'
import json, os, sys
res = sys.argv[1]
declared = {c.get("COMMAND_ID") for c in json.load(open(os.path.join(res, "Command.json")))["COMMAND_LIST"]}
# find.library.sh is this applet's shared library. It is sourced, never
# dispatched, but it does not carry the lib. prefix OMC filters on, so OMC
# synthesizes an inert find.library command for it. Exclude it here rather
# than let it read as an undeclared handler.
scripts = {f[:-3] for f in os.listdir(os.path.join(res, "Scripts"))
           if f.endswith(".sh") and not f.startswith(("lib.", "lib_"))}
scripts.discard("find.library")
print(" ".join(sorted(scripts - declared)))
PY
)
check "no handler script is undeclared" "" "$_missing_decl"

_missing_script=$(run_py "$APP_RESOURCES" <<'PY'
import json, os, sys
res = sys.argv[1]
cmds = json.load(open(os.path.join(res, "Command.json")))["COMMAND_LIST"]
files = set(os.listdir(os.path.join(res, "Scripts")))
print(" ".join(sorted(c["COMMAND_ID"] for c in cmds
                      if c.get("EXECUTION_MODE", "").startswith("exe_script_file")
                      and c.get("COMMAND_ID") and c["COMMAND_ID"] + ".sh" not in files)))
PY
)
check "and no script-file command lacks its script" "" "$_missing_script"

section "the folder-open command still declares the variable it reads"
# find.open.from.file.browser is exe_script_file, whose script body OMC does not
# scan. The COMMAND entry is what OMC's prescan sees, and it does two jobs: it
# exports OMC_DLG_CHOOSE_FOLDER_PATH, and it is what makes OMC present the
# choose-folder panel in the first place. Drop it and File > Open shows no
# panel at all and does nothing.
check "the export declaration survived the plist-to-json conversion" "1" \
    "$(run_py "$APP_RESOURCES" <<'PY'
import json, os, sys
cmds = json.load(open(os.path.join(sys.argv[1], "Command.json")))["COMMAND_LIST"]
c = [x for x in cmds if x.get("COMMAND_ID") == "find.open.from.file.browser"][0]
print(int(any("OMC_DLG_CHOOSE_FOLDER_PATH" in line for line in c.get("COMMAND", []))))
PY
)"
check "and the handler is what reads it" "yes" \
    "$(/usr/bin/grep -q 'OMC_DLG_CHOOSE_FOLDER_PATH' \
        "$APP_SCRIPTS/find.open.from.file.browser.sh" && echo yes || echo no)"

section "the menu bar is built from JSON, not from a nib"
# Info.plist is the switch: OMC only builds the bar programmatically (and only
# then reads MainMenu.json) when NSMainNibFile is absent.
check "Info.plist does not name a main nib" "yes" \
    "$(/usr/libexec/PlistBuddy -c 'Print :NSMainNibFile' "$OMCTEST_APP/Contents/Info.plist" \
        >/dev/null 2>&1 && echo no || echo yes)"
check "NSPrincipalClass is still NSApplication" "NSApplication" \
    "$(/usr/libexec/PlistBuddy -c 'Print :NSPrincipalClass' "$OMCTEST_APP/Contents/Info.plist" 2>/dev/null)"
# The nib hardcoded "About Find" / "Quit Find". The programmatic bar derives
# those from the process name, which is the executable's filename, so a bundle
# left on the stock OMCApplet binary name comes up with an App menu branded
# OMCApplet. Nothing warns about it; it is only visible by looking at the menu.
check "the executable is named for the app, not the stock OMC binary" "Find" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$OMCTEST_APP/Contents/Info.plist" 2>/dev/null)"
check "and that executable is the one in the bundle" "yes" \
    "$([ -x "$OMCTEST_APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
        "$OMCTEST_APP/Contents/Info.plist" 2>/dev/null)" ] && echo yes || echo no)"
check "MainMenu.json is present" "yes" \
    "$([ -f "$MENU_JSON" ] && echo yes || echo no)"
check_absent "and MainMenu.nib is gone" "$BASE_LPROJ/MainMenu.nib"
# The applet's own resources are fully nib-free now: the window comes from
# Find.json and the bar from MainMenu.json. Any .nib reappearing here is either
# a stale resource or a half-finished revert. Scoped to Contents/Resources
# because the embedded Abracode.framework legitimately ships its own nibs for
# OMC's input dialogs, progress bar and output window.
check "no nib remains in the applet's own resources" "" \
    "$(/usr/bin/find "$APP_RESOURCES" -name '*.nib' -print 2>/dev/null \
        | /usr/bin/sed "s|^$APP_RESOURCES/||" | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"

section "the menu document is a menu-bar document"
check "its root is an array" "list" \
    "$(run_py "$MENU_JSON" <<'PY'
import json, sys
print(type(json.load(open(sys.argv[1]))).__name__)
PY
)"
check "holding only menu-bar element types" "" \
    "$(run_py "$MENU_JSON" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
print(" ".join(sorted({e.get("type") for e in doc} - {"CommandMenu", "CommandGroup"})))
PY
)"

section "every menu item points at a command that exists"
# The wiring check. A typo in an actionID produces a menu item that looks fine
# and does nothing at all - no error, no log.
_dangling=$(run_py "$APP_RESOURCES" <<'PY'
import json, os, sys
res = sys.argv[1]
declared = {c.get("COMMAND_ID") for c in json.load(open(os.path.join(res, "Command.json")))["COMMAND_LIST"]}
declared.discard(None)
dangling = []
def walk(node):
    aid = node.get("properties", {}).get("actionID")
    if aid and aid not in declared:
        dangling.append(aid)
    for child in node.get("children", []):
        walk(child)
for element in json.load(open(os.path.join(res, "Base.lproj", "MainMenu.json"))):
    walk(element)
print(" ".join(sorted(dangling)))
PY
)
check "no menu item is wired to a missing command" "" "$_dangling"

# Positive control: the walk must actually reach a wired item, or the check above
# would pass just as well on a document with no items in it. Asserted as
# membership rather than equality so a second menu item later does not fail it.
check "and the walk saw the Open item's wiring" "yes" \
    "$(run_py "$MENU_JSON" <<'PY'
import json, sys
found = []
def walk(node):
    if node.get("properties", {}).get("actionID"):
        found.append(node["properties"]["actionID"])
    for child in node.get("children", []):
        walk(child)
for element in json.load(open(sys.argv[1])):
    walk(element)
print("yes" if "find.open.from.file.browser" in found else "no")
PY
)"

section "the Open item keeps the ellipsis character its title is matched by"
# OMC installs File > Open Recent itself, and OMCDropletController finds where to
# put it with indexOfItemWithTitle:@"Open<U+2026>" - by title, not by item id, and
# the replacement item carries no id. Spelling this title with three ASCII
# periods would leave the title unmatched and silently drop Open Recent.
check "the title uses U+2026, not three periods" "yes" \
    "$(run_py "$MENU_JSON" <<'PY'
import json, sys
titles = []
def walk(node):
    t = node.get("properties", {}).get("title")
    if t:
        titles.append(t)
    for child in node.get("children", []):
        walk(child)
for element in json.load(open(sys.argv[1])):
    walk(element)
print("yes" if any(t == "Open…" for t in titles) else "no")
PY
)"

omctest_end
