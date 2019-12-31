# Find.app
Find.app - macOS GUI applet for "find" command line tool

The applet is built with OMC engine:
https://github.com/abra-code/OMC

Getting started

1. Launch Find.app. Type "\*name\*" without quotes in "Name" edit field and hit enter. A window will open with a list of files with "name" word in their name found in your user directory. This includes non-indexed locations like ~/Library which macOS Spotlight Search does not produce in its search results.
2. Drag a folder to the app icon. This is now set as a new search location. Leave the "Name" field empty. Switch to "Attributes" tab and select "File Type: Directories". Switch to "Size" tab and select "Emptiness test: Only empty files or directories". Hit "Find" button at the bottom to find all empty folders in your chosen location.


Design Objectives, Goals and Non-Goals

"find" is a very powerful command line tool. It has a lot of options and complex syntax.
This app is a GUI "wrapper" to make the tool accessible to moderately advanced user.
Find.app does not let you do everything which "find" allows. Instead, it tries to provide a simplified interface for most useful features. What is "useful" is subjective and has been pre-selected for you by the author. The list of "options" and "primaries" are evaluated in accompanying spreadsheets - based on "man find" in macOS 10.14.6. That chosen set of "useful" functions has been exposed in single dialog user interface. In order to reduce the clutter a tabbed interface is used, logically grouping properties. One important choice which had to be made when designing the interface is whether to support full logical operations: AND, OR, NOT in all combinations. Supporting that would require a implementing a predicate editor in GUI (these are usually clunky) - it would be a lot of effort for little value: usually you search for things which satisfy a certain set of properties and you want to logically *AND* them. Sure it is easy to imagine that someone would want to find files which are "bigger than 100MB OR older than 10 weeks". There might be a good reason for doing it but *by design* Find.app does not give you an option to run a query like this. It will only let you find files "bigger than 100MB AND older than 10 weeks" because this is deemed the most frequent scenario and therefore most interesting.
