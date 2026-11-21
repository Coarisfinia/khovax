class_name CreditsTab
extends RichTextLabel
## The menu's Credits tab (#462): every loaded resource pack that gives the game a texture, model
## or sound, by its name, and under it each asset it gives with its author, source and license,
## read at runtime from the credit notes beside the assets in their packs (PackCredits, #2585), and
## shown where players can see it, as CC BY asks (#461). A player's pack credits what it brings; a
## note's title and its three fields are shown, not the rest of its history. It scrolls itself,
## with touch, a wheel, the keys or a controller once focused. Its look and layout live in its
## scene, credits_tab.tscn (#437): this script keeps only what it does. Above the credits it names
## the build's version (#744), so a player reporting a bug can say which build they play, and where
## the error log is (#1510), for them to attach to the report; on the web, where the log can't be
## found, a button above it saves the log as a file instead (ErrorLogButton, #1541). A button above
## both opens a new bug report with the version filled in (BugReportButton, #1405).

## The lines of a credit note the tab shows, by their start; each may continue on lines indented by
## two spaces below it.
const FIELDS: Array[String] = ["- **Author:**", "- **Source:**", "- **License:**"]
## What starts a note's title, and a field.
const TITLE: String = "# "
const FIELD: String = "- **"


func _ready() -> void:
	var credits: String = to_bbcode(ResourcePacks.credits())
	if credits.is_empty():
		credits = tr("The credits couldn't be read.")
	text = tr("[b]Version:[/b] %s") % BuildVersion.version() + "\n" + log_line() + credits


## The line naming where the error log is (ErrorLog), or "" where there's none to name (the web).
## Static, so it's translated through the TranslationServer rather than a node's tr().
static func log_line() -> String:
	var location: String = ErrorLog.location()
	if location.is_empty():
		return ""
	return TranslationServer.tr("[b]Error log:[/b] %s") % location.replace("[", "[lb]") + "\n"


## The packs' credits as BBCode: each pack's name as a heading, then each of its notes' titles in
## bold, with its fields as bullets with their bold names, a field's wrapped lines joined back into
## one, and code marks dropped; and how many of its files no note credits, if any. Static, so it's
## translated through the TranslationServer rather than a node's tr().
static func to_bbcode(credits: Array[PackCredits]) -> String:
	var shown: Array[String] = []
	for pack: PackCredits in credits:
		var heading: String = TranslationServer.tr("Resource pack: %s") % pack.pack_name
		shown.append("\n[b][u]%s[/u][/b]" % heading.replace("[", "[lb]"))
		for note: String in pack.notes:
			shown.append(note_bbcode(FileAccess.get_file_as_string(note)))
		if not pack.uncredited.is_empty():
			var count: int = pack.uncredited.size()
			var missing: String = TranslationServer.tr_n(
				"%d of its files has no credit note.", "%d of its files have no credit note.", count
			)
			shown.append(missing % count)
	return "\n".join(shown)


## One credit note's title and fields as BBCode, the first of each field, its other lines left
## out; "" for a note that doesn't start with its title.
static func note_bbcode(markdown: String) -> String:
	var lines: PackedStringArray = markdown.replace("\r", "").split("\n")
	if not lines[0].begins_with(TITLE):
		return ""
	var shown: Array[String] = [_bbcode_line(lines[0].strip_edges())]
	for field: String in FIELDS:
		var at: int = _first(lines, field)
		if at < 0:
			continue
		var joined: String = lines[at].strip_edges()
		var next: int = at + 1
		while next < lines.size() and lines[next].begins_with("  "):
			joined += " " + lines[next].strip_edges()
			next += 1
		shown.append(_bbcode_line(joined))
	return "\n".join(shown)


## The index of the first of `lines` starting with `start`, or -1.
static func _first(lines: PackedStringArray, start: String) -> int:
	for i: int in lines.size():
		if lines[i].begins_with(start):
			return i
	return -1


## One line of a credit note as BBCode: its title, or one of its fields.
static func _bbcode_line(line: String) -> String:
	var plain: String = line.replace("[", "[lb]").replace("`", "")
	if plain.begins_with(TITLE):
		return "\n[b]%s[/b]" % plain.trim_prefix(TITLE)
	# "- **Author:** name": the field's name in bold, then its value with any other marks dropped.
	var name_end: int = plain.find("**", FIELD.length())
	if not plain.begins_with(FIELD) or name_end < 0:
		return plain.replace("**", "")
	var field: String = plain.substr(FIELD.length(), name_end - FIELD.length())
	return "• [b]%s[/b]%s" % [field, plain.substr(name_end + 2).replace("**", "")]
