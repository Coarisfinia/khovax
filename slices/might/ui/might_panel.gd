class_name MightPanel
extends VBoxContainer
## The player's Might on the menu's Character tab (#509): the number and each part it's made of,
## so the player sees where it comes from (Might). Only the carried monsters' part exists yet; gear,
## abilities and boons add their lines with their parts. It only reads the profile, and keeps up
## with it while shown.

const TITLE: String = "Might"
const TOTAL_TEXT: String = "Might: %d"
const MONSTERS_TEXT: String = "From your carried monsters: %d"

## Whose Might is shown: this machine's player's profile.
var holder: ProfileHolder
## What the panel shows, one line each. Kept here so tests can read it.
var shown: Array[String] = []
var _species: Dictionary[String, Species] = {}
var _lines: VBoxContainer


func _ready() -> void:
	var species: SpeciesData = SpeciesContent.load_species()
	if not species.problem.is_empty():
		push_warning("the species can't be read, so Might counts no monsters: " + species.problem)
	_species = species.species
	add_child(GameMenu.label(TITLE))
	_lines = VBoxContainer.new()
	add_child(_lines)
	refresh()


func _process(_delta: float) -> void:
	# Only while the tab is shown: the menu is open on it.
	if is_visible_in_tree():
		refresh()


## Shows the Might as it is now; builds the lines anew only when they changed.
func refresh() -> void:
	var profile: Profile = Profile.new()
	if holder != null and holder.keeper != null:
		profile = holder.keeper.profile
	var lines: Array[String] = [
		TOTAL_TEXT % Might.of(profile, _species),
		MONSTERS_TEXT % Might.monsters_part(profile, _species),
	]
	if lines == shown:
		return
	shown = lines
	for line: Node in _lines.get_children():
		_lines.remove_child(line)
		line.queue_free()
	for line: String in lines:
		_lines.add_child(GameMenu.label(line))
