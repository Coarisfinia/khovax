class_name SpeciesAscension
extends RefCounted
## What a species ascends into (#1246, the name for a species growing into its grown form): a
## dominated monster of it ascends once it has reached `level` and is given the ascension material
## `material` (the owner's pick on #1235: a level and a material together). The material is a
## material like any other, held in the profile's materials; the game's tables drop it (the content
## flow checks one does). Giving it and the ascension itself are #1235.

## The species it ascends into, by id.
var into: String = ""
## The level it has to reach first. A monster starts at level 1, so at least 2.
var level: int = 0
## Its ascension material's item id.
var material: String = ""


## Reads a species file's `ascension` object `raw` into `ascension`; returns why it can't, or "".
## Whether `into` is a species, and not one that ascends back into this one, is SpeciesContent's.
static func read(raw: Variant, ascension: SpeciesAscension) -> String:
	if not raw is Dictionary:
		return "its ascension names the species it ascends into, a level and a material (#1252)"
	var data: Dictionary = raw
	var unknown: String = Content.unknown_field(data, ["into", "level", "material"])
	if not unknown.is_empty():
		return "its ascension's " + unknown
	ascension.into = Content.text_of(data.get("into"))
	ascension.level = JsonNumbers.whole(data.get("level"), 2, Fixed.MAX_AMOUNT, 0)
	ascension.material = Content.text_of(data.get("material"))
	if not Content.is_id(ascension.into) or not Content.is_id(ascension.material):
		return "its ascension names the species it ascends into and its material by their ids"
	if ascension.level == 0:
		return "its ascension's level is a whole number from 2 to %d" % Fixed.MAX_AMOUNT
	return ""
