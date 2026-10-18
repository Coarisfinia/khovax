class_name SpeciesData
extends RefCounted
## The species' and abilities' data as SpeciesContent reads it (#506: the slice holds its own kinds,
## so the shared Content never names them).

## Every species, by id.
var species: Dictionary[String, Species] = {}
## Every ability, by id (#222).
var abilities: Dictionary[String, Ability] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Reads one species file's text, named `file_id`, and adds it; returns why it can't, or "". Its id
## must be one no species read before has.
func add_species(file_id: String, text: String) -> String:
	var entry: Species = Species.parse(file_id, text)
	# A repeated id is refused as that first, whatever else is wrong with the file, as before #279.
	if not entry.id.is_empty() and species.has(entry.id):
		return "its id must match the file name and be unique"
	if entry.problem.is_empty():
		species[entry.id] = entry
	return entry.problem
