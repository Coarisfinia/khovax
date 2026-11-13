class_name Tonic
extends RefCounted
## A tonic (#2090, the potion design on #2049): the vial's own ingredients, a whitelist, so no other
## material ever goes into it (#2038). Its carrier carries every brew, each primary sets a brew's
## effect, and its catalyst goes only into a Shared brew. Its brews (TonicBrew) are read against it.

## Its schema, which says the fields a tonic file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/tonics/data/tonics.schema.json"
## The effects a primary can set, which the simulation applies (#2091).
const EFFECTS: Array[String] = ["mend", "regrowth", "ward", "quicken", "fortify"]
## The traits a brew can take, "none" for the base values.
const TRAITS: Array[String] = ["none", "strong", "lasting", "shared", "slow_release"]
## Who a brew can help: the player's out companion, or the player themselves.
const TARGETS: Array[String] = ["companion", "player"]
## The material categories never brewed (#2038, #2049, #2281): rock, ore and metal, whichever
## pack adds them.
const NEVER_BREWED_CATEGORIES: Array[String] = ["mineral", "metal"]
## The materials never brewed whatever their category: hide, which fits no sensible brew, the revive
## herb, which is the revive item, and the seed pod, the one respec item.
const NEVER_BREWED: Array[String] = ["hide", "revive_herb", "seed_pod"]

## Its id, by its file.
var id: String = ""
## The material every brew is carried in.
var carrier: String = ""
## The material only a Shared brew adds.
var catalyst: String = ""
## Each primary's effect, by the primary's material id.
var primaries: Dictionary[String, String] = {}
## The traits its brews may take.
var traits: Array[String] = []
## Each target's prefix for its brews' ids, by the target.
var targets: Dictionary[String, String] = {}


## Reads a tonic file's ingredients, traits and targets from `data` into this; returns why it can't,
## or "": every ingredient a material, none of them ever refused, and each in one role only.
func read(data: Dictionary) -> String:
	carrier = Content.text_of(data.get("carrier"))
	catalyst = Content.text_of(data.get("catalyst"))
	var raw: Variant = data.get("primaries")
	var given: Dictionary = raw if raw is Dictionary else {}
	for material: Variant in given:
		var effect: String = Content.text_of(given[material])
		if not EFFECTS.has(effect):
			return "its primary %s sets no effect a tonic has" % material
		primaries[str(material)] = effect
	var why: String = _read_choices(data.get("traits"), data.get("targets"))
	if why.is_empty():
		why = _ingredients_problem()
	return why


## Reads the traits `raw_traits` and the targets `raw_targets`; returns why it can't, or "".
func _read_choices(raw_traits: Variant, raw_targets: Variant) -> String:
	var listed: Array = raw_traits if raw_traits is Array else []
	for brew_trait: Variant in listed:
		var known: String = Content.text_of(brew_trait)
		if not TRAITS.has(known) or traits.has(known):
			return "its traits must each be a trait a tonic has, once"
		traits.append(known)
	var given: Dictionary = raw_targets if raw_targets is Dictionary else {}
	for target: Variant in given:
		var prefix: String = Content.text_of(given[target])
		if not TARGETS.has(str(target)) or not Content.is_id(prefix):
			return "its targets must each be a target a tonic has, with its brews' prefix"
		targets[str(target)] = prefix
	if primaries.is_empty() or traits.is_empty() or targets.is_empty():
		return "it needs primaries, traits and targets"
	return ""


## Why the ingredients break the design's rules, or "": the carrier, the catalyst and each primary
## are materials, distinct, and none of them is ever brewed, by its id or its category.
func _ingredients_problem() -> String:
	var ingredients: Array[String] = [carrier, catalyst]
	ingredients.append_array(primaries.keys())
	var materials: MaterialContent = MaterialContent.cached()
	for ingredient: String in ingredients:
		if NEVER_BREWED.has(ingredient):
			return "%s is never brewed (#2038, #2049)" % ingredient
		if not materials.ids.has(ingredient):
			return "its ingredient %s is no material" % ingredient
		var category: String = materials.categories.get(ingredient, "")
		if NEVER_BREWED_CATEGORIES.has(category):
			return "%s is a %s, never brewed (#2038, #2281)" % [ingredient, category]
		if ingredients.count(ingredient) > 1:
			return "%s is in it twice: one role per ingredient" % ingredient
	return ""
