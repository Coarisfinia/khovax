class_name TextNames
extends RefCounted
## Reads the names text tags (#733, TextTags) show from the content slices (#1612): the species,
## the factions, the gear, the people, the realms and the places they draw. It comes after them
## all, so `texts` names none of them and can come before the slices whose texts carry tags.
## game/ hands `load_tags` to TextTags once at start (TextNamesWiring), so every run that shows a
## text, the main scene's, a test's or a tool's, gets the names.


## Hands TextTags the names read from the game's content.
static func wire() -> void:
	TextTags.read_names_with(load_tags)


## The names every kind of tag shows, read from the content in the given directories.
static func load_tags(
	species_directory: String = SpeciesContent.DIR,
	faction_directory: String = FactionContent.DIR,
	gear_directory: String = GearContent.DIR,
	people_directory: String = PeopleContent.DIR,
) -> TextTags:
	var tags: TextTags = TextTags.new()
	var species: SpeciesContent = SpeciesContent.load_species(species_directory)
	var factions: FactionContent = FactionContent.load_factions(faction_directory)
	var gear: GearContent = GearContent.load_gear(gear_directory)
	var people: PeopleContent = PeopleContent.load_people(people_directory)
	tags.problem = species.problem + factions.problem + gear.problem + people.problem
	var monsters: Dictionary[String, String] = {}
	for id: String in species.species:
		monsters[id] = species.species[id].name
	var faction_names: Dictionary[String, String] = {}
	for id: String in factions.factions:
		faction_names[id] = factions.factions[id].name
	var gear_names: Dictionary[String, String] = {}
	var unique_names: Dictionary[String, String] = {}
	for id: String in gear.items:
		gear_names[id] = gear.items[id].name
		if gear.items[id].is_unique():
			unique_names[id] = gear.items[id].name
	var person_names: Dictionary[String, String] = {}
	for id: String in people.people:
		person_names[id] = people.people[id].name
	tags.names = {
		TextTags.MONSTER: monsters,
		TextTags.FACTION: faction_names,
		TextTags.GEAR: gear_names,
		TextTags.PERSON: person_names,
		TextTags.UNIQUE_ITEM: unique_names,
	}
	tags.names.merge(_realm_names())
	return tags


## The names of the realms and of the places they draw (#1175), by their kinds' words and ids: an
## instance a realm draws, and each region of its own that one of its blueprint's variants loads
## (#1448), such as a corrupted instance.
static func _realm_names() -> Dictionary[String, Dictionary]:
	var realm_names: Dictionary[String, String] = {}
	var place_names: Dictionary[String, String] = {}
	for realm: Realm in Realms.all():
		realm_names[realm.id] = realm.name
		for tile: Vector2i in realm.instances:
			var instance_name: String = realm.instances[tile]
			place_names[instance_name] = InstanceBlueprints.place_name(instance_name)
			var blueprint: Blueprint = InstanceBlueprints.blueprint(instance_name)
			if blueprint != null:
				for variant: String in blueprint.variant_codex:
					place_names[variant] = InstanceBlueprints.place_name(variant)
	return { TextTags.REALM: realm_names, TextTags.PLACE: place_names }
