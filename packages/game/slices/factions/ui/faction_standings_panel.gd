class_name FactionStandingsPanel
extends VBoxContainer
## The player's standing with each faction on the menu's Character tab (#533): every faction they
## aren't neutral with (Standings), in id order, with its name, the standing as a signed number and
## the rank the faction names it (Faction.rank_name), all in words, their text tags showing
## the names they stand for (#752), never in color alone (#68).
## Only the current rank's name, never the other ranks' (#484: they would spoil what's ahead). A
## faction the content no longer has shows by its id in words, without a rank. It only reads the
## profile, and keeps up with it while shown.

const TITLE: String = "Factions"
const NONE_TEXT: String = "Neutral with every faction"
## A faction's line: its name, the standing with its sign, and the rank's name.
const LINE_TEXT: String = "%s: %+d, %s"
## A faction's line when the content doesn't know it: its id in words and the standing.
const UNKNOWN_TEXT: String = "%s: %+d"

## Whose standings are shown: this machine's player's profile.
var holder: ProfileHolder
## What the panel shows, one line per faction. Kept here so tests can read it.
var shown: Array[String] = []
var _factions: Dictionary[String, Faction] = {}
var _rows: VBoxContainer


func _ready() -> void:
	var content: FactionContent = FactionContent.cached()
	if not content.problem.is_empty():
		push_warning("the factions can't be read, so their ranks aren't named: " + content.problem)
	_factions = content.factions
	add_child(GameMenu.label(TITLE))
	_rows = VBoxContainer.new()
	add_child(_rows)
	refresh()


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Shows the standings as they are now; builds the rows anew only when they changed.
func refresh() -> void:
	var lines: Array[String] = []
	if holder != null and holder.keeper != null:
		var standings: Dictionary[String, int] = holder.keeper.profile.standings.by_faction
		var ids: Array[String] = []
		ids.assign(standings.keys())
		ids.sort()
		for id: String in ids:
			# A standing moved back to neutral from another start (#1378) is kept, not listed.
			if standings[id] != 0:
				lines.append(line_of(id, standings[id]))
	if lines.is_empty():
		lines.append(NONE_TEXT)
	if lines == shown:
		return
	shown = lines
	GameMenu.show_lines(_rows, lines)


## The line for the standing `standing` with the faction `id`.
func line_of(id: String, standing: int) -> String:
	var faction: Faction = _factions.get(id)
	if faction == null:
		return UNKNOWN_TEXT % [id.capitalize(), standing]
	return LINE_TEXT % [
		TextTags.shown(faction.name), standing, TextTags.shown(faction.rank_name(standing)),
	]
