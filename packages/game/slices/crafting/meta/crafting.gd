class_name Crafting
extends RefCounted
## Crafting (#1349, at the base, #695): a player makes one of a recipe's material (RecipeContent)
## from the materials it needs, which are spent from their profile. Like ascending (#1235), it
## happens in the profile, outside the simulation, so it changes no replay. The base's crafting,
## once it's built, calls this and saves the profile (ProfileKeeper).


## Makes one of the material `recipe_id` in `profile`, spending what its recipe needs; returns why
## it can't, or "", and changes nothing when it can't.
static func craft(profile: Profile, recipe_id: String) -> String:
	var refusal: String = craft_problem(profile, recipe_id)
	if not refusal.is_empty():
		return refusal
	var recipe: Recipe = RecipeContent.cached().recipes[recipe_id]
	for need: String in recipe.needs:
		var _spent: String = profile.spend(need, recipe.needs[need])
	profile.materials[recipe_id] = profile.materials.get(recipe_id, 0) + 1
	return ""


## Why `profile` can't make one of the material `recipe_id` now, or "": it has a recipe, the
## player holds all it needs, and the profile can hold one more.
static func craft_problem(profile: Profile, recipe_id: String) -> String:
	var recipe: Recipe = RecipeContent.cached().recipes.get(recipe_id)
	if recipe == null:
		return "no recipe makes %s" % recipe_id
	for need: String in recipe.needs:
		if profile.materials.get(need, 0) < recipe.needs[need]:
			return "%s needs %d %s" % [recipe_id, recipe.needs[need], need]
	if profile.materials.get(recipe_id, 0) >= Profile.MAX_NUMBER:
		return "the profile can't hold more %s" % recipe_id
	return ""
