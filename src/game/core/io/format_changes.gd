class_name FormatChanges
extends RefCounted
## A save's format (#801): the names of the format changes it was written with, never a number.
## Each format keeps its changes in a folder of its own, `format_changes/`, one file per change:
## `<issue>-<slug>.md` with the issue in its frontmatter and one line on what changed. A reader
## asks whether a save has a change (`changes.has(name)`), never compares numbers, so two parallel
## changes never claim the same number and the order they merge in never matters. The folders are
## append-only, like the rule changes' (packages/game-checks/rules_changes_check.py), since saves
## name their files. Saves from before names held a `format` number instead, which each reader maps
## to the changes it meant.

## The key a save keeps its format change names under, unless its format already used it for
## something else (a replay's commands, ReplayFile).
const KEY: String = "changes"

## The names in each folder read so far, by folder.
static var _names: Dictionary[String, Array] = {}


## The names of the format changes in `folder`: its files' names without `.md`, in name order.
static func names_in(folder: String) -> Array[String]:
	if not _names.has(folder):
		var found: Array[String] = []
		for file_name: String in Content.file_names_in(folder):
			if file_name.ends_with(".md"):
				found.append(file_name.get_basename())
		_names[folder] = found
	var names: Array[String] = []
	names.assign(_names[folder])
	return names


## The format changes the save `read` was written with (under `key`), each one in `folder`. A save
## from before
## names (#801) holds a `format` number from 1 to one past `numbered`'s size instead, and had the
## first `format - 1` of `numbered`: the changes in the order they were numbered. Notes the problem
## in `read` and gives none when they don't hold, a change this build doesn't know (a newer
## build's) included.
static func read_from(
	read: DataReader,
	folder: String,
	numbered: Array[String],
	key: String = KEY,
) -> Array[String]:
	var changes: Array[String] = []
	if not read.data.has(key):
		var format: int = read.whole("format", 1, numbered.size() + 1)
		changes.assign(numbered.slice(0, format - 1))
		return changes
	var value: Variant = read.data[key]
	if not value is Array:
		read.fail("%s isn't a list" % key)
		return changes
	var known: Array[String] = names_in(folder)
	var items: Array = value
	for item: Variant in items:
		if not item is String or not known.has(item) or changes.has(item):
			read.fail("format change %s is saved twice or unknown to this build" % [item])
			changes.clear()
			return changes
		changes.append(item)
	return changes
