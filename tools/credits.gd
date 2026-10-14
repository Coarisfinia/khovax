# gdstyle:ignore-file=quality/no-debug-print
# The tool reports to whoever runs it (CI) on stderr; that is what it is for.
extends SceneTree
## Writes CREDITS.md from the source note every asset pack keeps next to its files
## (assets/<pack>/SOURCE.md): its title and its author, source and license lines (#70). CI runs it
## and fails when the committed CREDITS.md differs, so the credits can't drift from the assets:
## godot --headless --path . -s res://tools/credits.gd

const ASSETS: String = "res://assets/"
const TARGET: String = "res://CREDITS.md"
## The lines of a source note that go into the credits, by their start; each may continue on
## indented lines below it.
const FIELDS: Array[String] = ["- **Author:**", "- **Source:**", "- **License:**"]
const HEADER: String = """# Credits

The assets this game uses, with their authors and licenses. Generated from each pack's
`assets/<pack>/SOURCE.md` by `tools/credits.gd`; don't edit it by hand.
"""


func _init() -> void:
	var text: String = HEADER
	var failed: int = 0
	var packs: PackedStringArray = DirAccess.get_directories_at(ASSETS)
	packs.sort()
	for pack: String in packs:
		var entry: String = _entry(pack)
		if entry.is_empty():
			printerr("assets/%s/SOURCE.md lacks its title, author, source or license" % pack)
			failed += 1
		text += "\n" + entry
	var file: FileAccess = FileAccess.open(TARGET, FileAccess.WRITE)
	if file == null or not file.store_string(text):
		printerr("couldn't write CREDITS.md")
		failed += 1
	quit(1 if failed > 0 else 0)


## One pack's credits from its source note, or "" when the note lacks a title or a field.
func _entry(pack: String) -> String:
	var note: String = FileAccess.get_file_as_string(ASSETS + pack + "/SOURCE.md")
	var lines: PackedStringArray = note.split("\n")
	if lines.is_empty() or not lines[0].begins_with("# "):
		return ""
	var entry: String = "## %s\n\n- **Files:** `assets/%s/`\n" % [lines[0].trim_prefix("# "), pack]
	for field: String in FIELDS:
		var found: String = _field(lines, field)
		if found.is_empty():
			return ""
		entry += found
	return entry


## The field's line and its indented continuation lines, or "" when the note doesn't have it.
func _field(lines: PackedStringArray, field: String) -> String:
	for i: int in lines.size():
		if lines[i].begins_with(field):
			var found: String = lines[i].strip_edges(false, true) + "\n"
			var next: int = i + 1
			while next < lines.size() and lines[next].begins_with("  "):
				found += lines[next].strip_edges(false, true) + "\n"
				next += 1
			return found
	return ""
