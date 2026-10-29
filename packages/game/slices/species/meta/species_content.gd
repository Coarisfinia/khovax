class_name SpeciesContent
extends Content
## The species' content data (#279), which the species slice owns (#412): one JSONC file per
## species directly in its data/ (its own kind, so no folder repeats the slice's name, #442),
## checked against its schema there in CI. Everything else reads them through this; their abilities
## are AbilityContent's. It also holds what each species ascends into (#1252), a link between two
## species that only the whole content can check.

const DIR: String = "res://slices/species/data/"

## Every species, by id.
var species: Dictionary[String, Species] = {}
## Every species that ascends (#1252), by id: what into, at what level and with which material.
var ascensions: Dictionary[String, SpeciesAscension] = {}
var _specials: Dictionary[String, Ability] = {}
var _specials_read: bool = false


## Every species file in `directory`, read and checked.
static func load_species(directory: String = DIR) -> SpeciesContent:
	var content: SpeciesContent = SpeciesContent.new()
	content.read(directory)
	return content


## The species, read once per session (ContentCatalog); species that don't load are an error.
static func cached() -> SpeciesContent:
	return ContentCatalog.kept(DIR, _checked)


static func _checked() -> SpeciesContent:
	var content: SpeciesContent = load_species()
	if not content.problem.is_empty():
		push_error("the species don't load: " + content.problem)
	return content


## Every species' special (#410), by species id, from the abilities (AbilityContent), worked out
## the first time it's asked for. A special that doesn't load is an error, and its species has none.
func specials() -> Dictionary[String, Ability]:
	if _specials_read:
		return _specials
	_specials_read = true
	var abilities: AbilityContent = AbilityContent.cached()
	if not abilities.problem.is_empty():
		push_error("the abilities don't load: " + abilities.problem)
	for species_id: String in species:
		var special: Ability = abilities.abilities.get(species[species_id].special)
		if special == null or special.kind != Ability.SPECIAL:
			push_error("%s's special doesn't load" % species_id)
			continue
		_specials[species_id] = special
	return _specials


## The first form of `species_id`'s line (#1697): the species it ascended from, and that one's,
## back to one that ascends from none; the lowest id where two ascend into the same. Itself, for a
## species nothing ascends into.
func first_form(species_id: String) -> String:
	var form: String = species_id
	var before: String = _ascends_from(form)
	# The chains never come back round (ascension_problem), so this ends.
	while not before.is_empty():
		form = before
		before = _ascends_from(form)
	return form


## The lowest id of a species that ascends into `species_id`, or "" for none.
func _ascends_from(species_id: String) -> String:
	var found: String = ""
	for from: String in ascensions:
		if ascensions[from].into == species_id and (found.is_empty() or from < found):
			found = from
	return found


## Reads every species file in `directory`, then checks their ascensions against each other.
func read(directory: String) -> void:
	super.read(directory)
	if problem.is_empty():
		problem = ascension_problem()


## Its id must be one no species read before has.
func add(file_id: String, text: String) -> String:
	var entry: Species = Species.parse(file_id, text)
	# A repeated id is refused as that first, whatever else is wrong with the file, as before #279.
	if not entry.id.is_empty() and species.has(entry.id):
		return "its id must match the file name and be unique"
	if not entry.problem.is_empty():
		return entry.problem
	var data: Dictionary = Content.object_of(text)
	if data.has("ascension"):
		var ascension: SpeciesAscension = SpeciesAscension.new()
		var wrong: String = SpeciesAscension.read(data["ascension"], ascension)
		if not wrong.is_empty():
			return wrong
		ascensions[entry.id] = ascension
	species[entry.id] = entry
	return ""


## Why a species' ascension can't be (#1252), or "": it ascends into a species there is, never
## itself, and no chain of ascensions comes back to where it started.
func ascension_problem() -> String:
	for species_id: String in ascensions:
		var into: String = ascensions[species_id].into
		if not species.has(into) or into == species_id:
			return "%s ascends into %s, which isn't another species" % [species_id, into]
		var seen: Array[String] = [species_id]
		while ascensions.has(into):
			if seen.has(into):
				return "%s's ascensions come back to %s" % [species_id, into]
			seen.append(into)
			into = ascensions[into].into
	return ""
