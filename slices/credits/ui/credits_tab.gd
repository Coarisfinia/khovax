class_name CreditsTab
extends RichTextLabel
## The menu's Credits tab (#462): every asset pack the game uses, with its author, source and
## license, read from CREDITS.md as tools/credits.gd generates it (so it can't drift), and shown
## where players can see it, as CC BY asks (#461). It shows each pack's heading and fields, but not
## the file's own note on how it's made nor the repository paths. It scrolls itself, with touch, a
## wheel, the keys or a controller once focused.

const PATH: String = "res://CREDITS.md"
## What starts a pack's heading, and the field that names files in the repository.
const PACK: String = "## "
const FILES: String = "- **Files:**"
const UNREADABLE: String = "The credits couldn't be read."


func _ready() -> void:
	bbcode_enabled = true
	focus_mode = Control.FOCUS_ALL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var markdown: String = FileAccess.get_file_as_string(PATH)
	text = to_bbcode(markdown) if not markdown.is_empty() else UNREADABLE


## CREDITS.md's packs as BBCode: a bold heading each, then its fields as bullets with their bold
## names, a field's wrapped lines joined back into one, and code marks dropped.
static func to_bbcode(markdown: String) -> String:
	var lines: Array[String] = []
	var started: bool = false
	for line: String in markdown.split("\n"):
		started = started or line.begins_with(PACK)
		if not started or line.strip_edges().is_empty():
			continue
		if line.begins_with("  ") and not lines.is_empty():
			lines[-1] += " " + line.strip_edges()
		else:
			lines.append(line)
	var shown: Array[String] = []
	for line: String in lines:
		if line.begins_with(FILES):
			continue
		shown.append(_bbcode_line(line))
	return "\n".join(shown)


## One line of CREDITS.md as BBCode: a pack's heading, or one of its fields.
static func _bbcode_line(line: String) -> String:
	var plain: String = line.replace("[", "[lb]").replace("`", "")
	if plain.begins_with(PACK):
		return "\n[b]%s[/b]" % plain.trim_prefix(PACK)
	var parts: PackedStringArray = plain.trim_prefix("- ").split("**")
	# "**Author:** name" splits into "", "Author:", " name".
	if parts.size() == 3:
		return "• [b]%s[/b]%s" % [parts[1], parts[2]]
	return plain
