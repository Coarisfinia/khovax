class_name FactionStandingsPanel
extends VBoxContainer
## The player's standing with each faction on the menu's Character tab (#533): every faction they
## aren't neutral with whose standing moved from its start or whose name they've met (`met`, #1383),
## in id order, with its name, the standing as a signed number and
## the rank the faction names it (Faction.rank_name), all in words, their text tags showing
## the names they stand for (#752), never in color alone (#68).
## Only the current rank's name, never the other ranks' (#484: they would spoil what's ahead). A
## faction the content no longer has shows by its id in words, without a rank. Each line is a
## NameLinks (#1447): a known faction's name is a link to its codex page, whose `name_selected` and
## `name_shown` the panel raises as its own. It only reads the profile, and keeps up with it while
## shown.

## A faction's name in a line was selected (NameLinks): TextTags.FACTION and its id.
signal name_selected(kind: String, id: String)
## A line showed a faction's name: the player met it (#1174).
signal name_shown(kind: String, id: String)

## This machine's player's standings (Standings), handed in by the profile (ProfilePanelsTie),
## whose slice comes after this one; none without it.
var standings: Callable = Callable()
## What the panel shows, one line per faction, in words. Kept here so tests can read it.
var shown: Array[String] = []
## The lines as text with text tags, the faction's name tagged, as the rows show them.
var tagged: Array[String] = []
## The ids of the factions whose names this machine's player has met (#1383), as an Array[String]:
## handed in by the codex (FactionMetTie), whose slice comes after this one; none without it.
var met: Callable = Callable()
var _factions: Dictionary[String, Faction] = {}
var _rows: VBoxContainer


func _ready() -> void:
	var content: FactionContent = FactionContent.cached()
	if not content.problem.is_empty():
		push_warning("the factions can't be read, so their ranks aren't named: " + content.problem)
	_factions = content.factions
	add_child(MenuWidgets.label(tr("Factions")))
	_rows = VBoxContainer.new()
	add_child(_rows)
	# No rows until it's shown (_process): showing a row meets its faction (#1447), which a row
	# built while the menu is closed would do before the player sees the name.


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Shows the standings as they are now; builds the rows anew only when they changed.
func refresh() -> void:
	var lines: Array[String] = []
	if standings.is_valid():
		var held: Standings = standings.call()
		var ids: Array[String] = []
		ids.assign(held.by_faction.keys())
		if met.is_valid():
			for id: String in met.call():
				if not ids.has(id):
					ids.append(id)
		ids.sort()
		for id: String in ids:
			# Neutral isn't listed, even a standing moved back to it from another start (#1378).
			if held.of(id) != 0:
				lines.append(line_of(id, held.of(id)))
	# While no standing has moved from its start: not "neutral", since some factions start off it
	# (#1378), and without naming one the player may not have met.
	if lines.is_empty():
		lines.append(tr("No faction standings yet"))
	if lines == tagged:
		return
	tagged = lines
	shown.clear()
	for old: Node in _rows.get_children():
		_rows.remove_child(old)
		old.queue_free()
	for line: String in lines:
		shown.append(TextTags.shown(line))
		_add_row(line)


## Adds a row showing `line`, a text with text tags, its names as links.
func _add_row(line: String) -> void:
	var row: NameLinks = NameLinks.new()
	var _selected: int = row.name_selected.connect(name_selected.emit)
	var _met: int = row.name_shown.connect(name_shown.emit)
	_rows.add_child(row)
	row.show_tagged(line)


## The line for the standing `standing` with the faction `id`: a text with text tags, the
## faction's name tagged, the standing with its sign, and the rank's name; one the content doesn't
## know shows its id in words and the standing.
func line_of(id: String, standing: int) -> String:
	var faction: Faction = _factions.get(id)
	var signed: String = "%+d" % standing
	if faction == null:
		var unknown: String = tr("{faction}: {standing}")
		return unknown.format({ "faction": id.capitalize(), "standing": signed })
	return tr("{faction}: {standing}, {rank}").format(
		{
			"faction": TextTags.tag(TextTags.FACTION, id),
			"standing": signed,
			"rank": tr(faction.rank_name(standing)),
		}
	)
