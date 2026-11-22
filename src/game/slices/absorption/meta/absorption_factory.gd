class_name AbsorptionFactory
extends RefCounted
## Builds an instance's absorption feature (#2412, #823) from the species data: which species
## list AbsorptionFeature.CORE_SKILL in their core list (#2409), and each species' permanent base
## stats and attack kit for form snapshots.


static func build(_setup: FeatureSetup) -> AbsorptionFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var absorbers: Array[String] = _absorber_species(content)
	var templates: Dictionary[String, AbsorbedForm] = {}
	for species_id: String in content.species:
		templates[species_id] = _template_of(content.species[species_id])
	return AbsorptionFeature.new(absorbers, templates)


## Whether `region`'s legend or `wild_species` roster can place a wild monster whose species has
## AbsorptionFeature.CORE_SKILL: only then does an instance need the feature.
static func has_absorber(region: Region, wild_species: Dictionary = {}) -> bool:
	var absorbers: Array[String] = _absorber_species(SpeciesContent.cached())
	if absorbers.is_empty():
		return false
	for species_id: Variant in wild_species:
		if absorbers.has(str(species_id)):
			return true
	var placed: Dictionary[Vector2i, String] = region.placed(WildSpotPlacements.KIND)
	for spot: Vector2i in placed:
		var named: WildSpot = WildSpot.read(placed[spot])
		if named != null and absorbers.has(named.species):
			return true
	return false


## The species ids whose core list includes AbsorptionFeature.CORE_SKILL, sorted.
static func _absorber_species(content: SpeciesContent) -> Array[String]:
	var ids: Array[String] = []
	for species_id: String in content.cores:
		var listed: Array = content.cores[species_id]
		if listed.has(AbsorptionFeature.CORE_SKILL):
			ids.append(species_id)
	ids.sort()
	return ids


## Permanent base form snapshot template for `entry` (species stats and kit, no temporary state).
static func _template_of(entry: Species) -> AbsorbedForm:
	var form: AbsorbedForm = AbsorbedForm.new()
	form.species = entry.id
	form.hp = entry.hp
	form.strength = entry.strength
	form.speed = entry.speed
	form.strike_type = entry.strike_type
	form.special = entry.special
	for passive: String in [entry.player_passive, entry.self_passive]:
		if not passive.is_empty():
			form.passives.append(passive)
	return form
