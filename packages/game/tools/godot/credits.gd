# gdstyle:ignore-file=quality/no-debug-print
# The tool reports to whoever runs it (CI) on stderr; that is what it is for.
extends SceneTree
## Writes CREDITS.md from the source note every asset pack keeps next to its files
## (assets/<pack>/SOURCE.md): its title and its author, source and license lines (#70). CI runs it
## and fails when the committed CREDITS.md differs, so the credits can't drift from the assets:
## godot --headless --path packages/game -s res://tools/godot/credits.gd
##
## It also refuses an asset under the Quaternius Asset License (QAL, #1954): the author's site,
## quaternius.com, offers its files under it since 2026-08-28, and it forbids redistributing them
## as assets, which this public repository and a shareable resource pack do. A pack whose source
## names quaternius.com, whose license names the QAL, or whose license file is the QAL's text fails,
## unless its note has an `- **Owner's OK:**` line naming where the owner allowed it. The author's
## models taken from Poly Pizza while it showed them as CC0 (assets/quaternius-items/) stay allowed.

const ASSETS: String = "res://assets/"
const TARGET: String = "res://CREDITS.md"
## The lines of a source note that go into the credits, by their start; each may continue on
## indented lines below it.
const FIELDS: Array[String] = ["- **Author:**", "- **Source:**", "- **License:**"]
const SOURCE: String = "- **Source:**"
const LICENSE: String = "- **License:**"
const OWNERS_OK: String = "- **Owner's OK:**"
const HEADER: String = """# Credits

The assets this game uses, with their authors and licenses. Generated from each pack's
`assets/<pack>/SOURCE.md` by `tools/godot/credits.gd`; don't edit it by hand.
"""

## The author's own license by any of its names ("Quaternius Asset License", "Quaternius's own
## licence", "Quaternius License"), in any case, or its short name QAL in capitals only.
var _qal: RegEx = RegEx.create_from_string(
	"(?i:quaternius(?:'s)?\\s+(?:own\\s+)?(?:asset\\s+)?licen[cs]e)|\\bQAL\\b"
)


func _init() -> void:
	var text: String = HEADER
	var failed: int = 0
	var packs: PackedStringArray = DirAccess.get_directories_at(ASSETS)
	packs.sort()
	if packs.is_empty():
		printerr("no asset packs in assets/: the credits would be empty")
		failed += 1
	for pack: String in packs:
		var entry: String = _entry(pack)
		if entry.is_empty():
			printerr("assets/%s/SOURCE.md lacks its title, author, source or license" % pack)
			failed += 1
		text += "\n" + entry
		for reason: String in _qal_refusals(pack):
			printerr(
				(
					"assets/%s/SOURCE.md: %s (#1954): it forbids redistributing the asset, so it"
					+ " stays out of the repository and every pack unless the owner allows it"
					+ " (an `- **Owner's OK:**` line naming where)"
				)
				% [pack, reason]
			)
			failed += 1
	var file: FileAccess = FileAccess.open(TARGET, FileAccess.WRITE)
	if file == null or not file.store_string(text):
		printerr("couldn't write CREDITS.md")
		failed += 1
	quit(1 if failed > 0 else 0)


## One pack's credits from its source note, or "" when the note lacks a title or a field.
func _entry(pack: String) -> String:
	var lines: PackedStringArray = _note_lines(pack)
	if lines.is_empty() or not lines[0].begins_with("# "):
		return ""
	var entry: String = "## %s\n\n- **Files:** `assets/%s/`\n" % [lines[0].trim_prefix("# "), pack]
	for field: String in FIELDS:
		var found: String = _field(lines, field)
		if found.is_empty():
			return ""
		entry += found
	return entry


## Why the pack may not be here under the Quaternius Asset License, or none when it may. Every
## source and license line counts, not only the first, and every license file in the pack's folders.
func _qal_refusals(pack: String) -> Array[String]:
	var found: Array[String] = []
	var lines: PackedStringArray = _note_lines(pack)
	if not _field(lines, OWNERS_OK).is_empty():
		return found
	# The author's own downloads (their site, or another store) are under the QAL; only Poly
	# Pizza's CC0 pages are not.
	var source: String = _every_field(lines, SOURCE)
	if source.containsn("quaternius") and not source.containsn("poly.pizza"):
		found.append("its source is the author's own, whose files are under the QAL")
	if _qal.search(_every_field(lines, LICENSE)) != null:
		found.append("its license is the Quaternius Asset License (QAL)")
	for path: String in _license_files(ASSETS + pack):
		if _qal.search(FileAccess.get_file_as_string(path)) != null:
			found.append("its license file %s is the Quaternius Asset License (QAL)" % path)
	return found


## Every occurrence of the field in the note, each with its continuation lines.
func _every_field(lines: PackedStringArray, field: String) -> String:
	var found: String = ""
	for i: int in lines.size():
		if lines[i].begins_with(field):
			found += _block(lines, i)
	return found


## The license files (LICENSE* or LICENCE*, in any case, not Godot's .import files) in the folder
## and every folder below it.
func _license_files(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.to_upper().begins_with("LICEN") and not file.ends_with(".import"):
			found.append(folder + "/" + file)
	for below: String in DirAccess.get_directories_at(folder):
		found.append_array(_license_files(folder + "/" + below))
	return found


## The pack's source note, line by line.
func _note_lines(pack: String) -> PackedStringArray:
	# Line endings normalized, so a note saved on Windows gives the same credits.
	var path: String = ASSETS + pack + "/SOURCE.md"
	return FileAccess.get_file_as_string(path).replace("\r", "").split("\n")


## The field's line and its continuation lines (indented by two spaces), or "" when the note
## doesn't have it or leaves it empty.
func _field(lines: PackedStringArray, field: String) -> String:
	for i: int in lines.size():
		if lines[i].begins_with(field) and not lines[i].trim_prefix(field).strip_edges().is_empty():
			return _block(lines, i)
	return ""


## The line at i and its continuation lines (indented by two spaces), right-trimmed.
func _block(lines: PackedStringArray, i: int) -> String:
	var found: String = lines[i].strip_edges(false, true) + "\n"
	var next: int = i + 1
	while next < lines.size() and lines[next].begins_with("  "):
		found += lines[next].strip_edges(false, true) + "\n"
		next += 1
	return found
