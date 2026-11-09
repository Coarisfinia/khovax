class_name Recipe
extends RefCounted
## A crafting recipe (#1349): one of the material `id` names, made from the materials it `needs`.
## RecipeContent reads it, and Crafting makes it from a player's profile.

## The material it makes, by id: one of it each time.
var id: String = ""
## The materials it's made from, by id: how many of each.
var needs: Dictionary[String, int] = {}


## Reads a recipe file's `needs` object `raw` into this; returns why it can't, or "": at least one
## material, each named by its id with a whole count from 1, and never the material it makes.
func read_needs(raw: Variant) -> String:
	var data: Dictionary = raw if raw is Dictionary else {}
	if data.is_empty():
		return "its needs name one or more materials, each with a count"
	for key: Variant in data:
		var need: String = Content.text_of(key)
		var count: int = JsonNumbers.whole(data[key], 1, Profile.MAX_NUMBER, 0)
		if not Content.is_id(need) or count == 0:
			return "its needs give each material's id a whole count from 1"
		if need == id:
			return "it needs %s, the material it makes" % id
		needs[need] = count
	return ""
