class_name InstanceBlueprints
extends RefCounted
## Instance blueprints (#117): what an instance is loaded from, by name. A blueprint is a region and
## the features an instance has, in their step order. The region is a fixed region file,
## regions/<name>.md, or region pieces in regions/<name>/ that the seed arranges and, if the
## blueprint is turned, turns (#57, #127). The players start on the region's starts. A blueprint
## switches game rules on and off by listing them, and they can change during a session. One with a
## chest loot table has treasure chests too, rolling on it (#124, #694), and the loot on its ground
## rolls on its instance loot table (#90, #203). What tells blueprints apart is content data, one
## file each (Blueprint, #823).

## The names the code and the tests load blueprints by; the blueprints themselves are the files in
## BlueprintContent.DIR. The playground (#338), which only the tests play (#712).
const BASIC: String = "basic"
## The load test's (#101).
const LOAD: String = "load"
## The glade, where the world starts (#712).
const GLADE: String = "glade"
## A boss-style arena (#127).
const ARENA: String = "arena"
## Room for the upcoming features (#689).
const FOREST: String = "forest"
const OUTPOST: String = "outpost"
## The corrupted glade (#541): the flag that corrupts the glade, and the variant it chooses
## (glade.jsonc). Its corrupting monster emits GLADE_PURIFIED when it faints
## (regions/glade_corrupted.md), whose flag purifies it.
const CORRUPTED_GLADE: String = "glade_corrupted"
const GLADE_PURIFIED: String = "glade_purified"
const REGIONS: String = "res://regions/"
## The region piece an arranged region starts from, holding the players' starts.
const START_PIECE: String = "start.md"

## The blueprints' content data, read on first use and kept: it doesn't change while the game runs.
static var _content: BlueprintContent = null


## The name of every blueprint there is, in file name order.
static func names() -> Array[String]:
	var all: Array[String] = []
	all.assign(_loaded().blueprints.keys())
	return all


## The named blueprint's content data, or null when there's none.
static func blueprint(instance_name: String) -> Blueprint:
	return _loaded().blueprints.get(instance_name)


## Whether a blueprint of this name exists.
static func exists(instance_name: String) -> bool:
	return _loaded().blueprints.has(instance_name)


## The variant of the named blueprint that the world's `flags` choose (Blueprint.variants), or "".
static func variant(instance_name: String, flags: Array[String]) -> String:
	var named: Blueprint = blueprint(instance_name)
	if named == null:
		return ""
	for chosen_by: PackedStringArray in named.variants:
		if flags.has(chosen_by[0]):
			return chosen_by[1]
	return ""


## A new instance from the named blueprint, as its state, with `players` players in slots 0 and
## up (none for an instance loaded before anyone walks in, #148), from its `variant_name`'s region
## ("" for its own), or null (with an error) for an unknown name, an unreadable region, more players
## than the region has starts, or an invalid feature order.
static func create(
	instance_name: String,
	seed_value: int,
	players: int = 1,
	variant_name: String = "",
) -> GameState:
	var region: Region = _region_for(instance_name, seed_value, players, variant_name)
	if region == null:
		return null
	var species: SpeciesData = SpeciesContent.load_species()
	if not species.problem.is_empty():
		push_error("the species don't load: " + species.problem)
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		_health(species),
		_wild_monsters(instance_name, species),
		DominationFeature.new(),
		# After domination, whose waiting rings it breaks, and before enrage, which enrages the
		# wild monsters of a ring that broke.
		WildAttackFeature.new(),
		# After domination, whose rings' wild monsters it hurts (#692).
		_spikes(),
		_domination_loot(instance_name),
		EnrageFeature.new(),
		FogFeature.new(),
	]
	ordered.append_array(_for_region(region))
	if not blueprint(instance_name).chest_table.is_empty():
		var chest_table: LootTable = _chest_table(instance_name)
		var ground_table: LootTable = _blank_table(instance_name)
		if chest_table == null or ground_table == null:
			push_error("instance %s's chest or instance loot table doesn't load" % instance_name)
			return null
		ordered.append(ChestFeature.new(chest_table, ground_table))
	# The companions and the features built on them. A companion whose player walks out through an
	# exit goes with them whatever the order: the world moves it after the tick (#716).
	ordered.append(_companions(species))
	# After the companions, so a swap can't pick a monster that fainted (#597).
	ordered.append(CompanionSwapFeature.new())
	# After the companions too, whose fainted ones a revive item brings back (#656).
	ordered.append(ReviveItemFeature.new())
	ordered.append_array(_attacks(species))
	# The harvest after the specials, whose strikes fell the wild monsters it drops materials for.
	ordered.append_array([_harvest(instance_name), _dialogs(), _territory()])
	var state: GameState = GameState.new(region, seed_value, ordered)
	if not state.problem.is_empty():
		push_error("instance %s has an invalid feature order: %s" % [instance_name, state.problem])
		return null
	for slot: int in players:
		# Can't be refused: the count is checked above and every slot is new.
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	return state


## The region a new instance of the named blueprint's `variant_name` is loaded with for
## `seed_value` and `players` players, or null (with an error) for an unknown name, an unreadable
## region or more players than the region has starts.
static func _region_for(
	instance_name: String,
	seed_value: int,
	players: int,
	variant_name: String,
) -> Region:
	if not exists(instance_name):
		push_error("unknown instance blueprint: " + instance_name)
		return null
	var region: Region = region_of(instance_name, seed_value, variant_name)
	if not region.problem.is_empty():
		push_error("instance %s has a broken region: %s" % [instance_name, region.problem])
		return null
	if players < 0 or players > region.starts.size():
		var limits: Array = [instance_name, region.starts.size(), players]
		push_error("instance %s takes 0 to %d players, not %d" % limits)
		return null
	return region


## The features an instance has because of what its region holds: exits, triggers, region pieces
## to enter, wild monsters in hiding, people to talk to.
static func _for_region(region: Region) -> Array[Feature]:
	var features: Array[Feature] = []
	if not region.exits.is_empty():
		features.append(ExitFeature.new())
	if not region.triggers.is_empty():
		features.append(TriggerFeature.new())
	if not region.piece_of.is_empty():
		features.append(EnteringFeature.new())
	if HidingFeature.has_hiding(region):
		features.append(HidingFeature.new())
	if not region.placed(NpcPlacements.KIND).is_empty():
		features.append(NpcFeature.new())
	return features


## The named blueprint's region for `seed_value`, from its `variant_name`'s region (#529) or, for
## "", its own: the region file as it is, or its region pieces arranged, the start piece first and
## the others by file name, and turned if the blueprint is. Its `problem` says what's wrong.
static func region_of(instance_name: String, seed_value: int, variant_name: String = "") -> Region:
	var region_name: String = variant_name if not variant_name.is_empty() else instance_name
	var path: String = REGIONS + region_name + ".md"
	if FileAccess.file_exists(path):
		return read_region(FileAccess.get_file_as_string(path))
	var folder: String = REGIONS + region_name + "/"
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".md") and file != START_PIECE:
			files.append(file)
	files.sort()
	files.push_front(START_PIECE)
	var pieces: Array[Region] = []
	pieces.assign(files.map(func(file: String) -> Region: return _piece(folder + file)))
	for piece: Region in pieces:
		if not piece.problem.is_empty():
			return piece
	var named: Blueprint = blueprint(instance_name)
	return RegionArranger.arrange(pieces, seed_value, named != null and named.turned)


## The region a Markdown region document describes (RegionDocument), with what every slice places
## on its ground read by that slice (#824).
static func read_region(text: String) -> Region:
	var readers: Array[PlacementReader] = [NpcPlacements.new(), ChestPlacements.new()]
	return RegionDocument.parse(text, readers)


## Why the named blueprint's exits don't hold together, or "" (#140): each leads to a blueprint that
## exists and has an exit leading back on the opposite side, so a way out always has a way back.
## The web is checked by the world flow, not each time an instance loads.
static func exit_problem(instance_name: String) -> String:
	var region: Region = region_of(instance_name, 0)
	for i: int in region.exits.size():
		var target: String = region.exit_blueprints[i]
		if not exists(target):
			return "%s's exit leads to %s, which doesn't exist" % [instance_name, target]
		var back: Region = region_of(target, 0)
		var side: int = posmod(region.exits[i].z + 3, Hex.DIRECTIONS.size())
		var found: bool = false
		for j: int in back.exits.size():
			found = found or (back.exit_blueprints[j] == instance_name and back.exits[j].z == side)
		if not found:
			return "%s has no exit back to %s on side %d" % [target, instance_name, side]
	return ""


## The basic instance, as `create` makes it.
static func basic(seed_value: int, players: int = 1) -> GameState:
	return create(BASIC, seed_value, players)


## The companion feature (#338) with every species' reach, from its stats in `content`.
static func _companions(content: SpeciesData) -> CompanionFeature:
	var reaches: Dictionary[String, int] = {}
	for species_id: String in content.species:
		var stats: Species = content.species[species_id]
		reaches[species_id] = CompanionFeature.reach_of(stats.hp, stats.strength, stats.speed)
	return CompanionFeature.new(reaches)


## The health feature (#455) with every species' HP, from the species `content`, for companions and
## wild monsters (#835). It steps before the wild monsters and every feature that hurts or heals.
static func _health(content: SpeciesData) -> HealthFeature:
	return HealthFeature.new(_max_hps(content))


## The dialog feature (#635) with every dialog's answers, by code, from the dialogs' content data.
static func _dialogs() -> DialogFeature:
	var content: DialogContent = DialogContent.load_dialogs()
	if not content.problem.is_empty():
		push_error("the dialogs don't load: " + content.problem)
	return DialogFeature.new(content.answers)


## The territory feature (#638) with every territory a quest hands over, by code, from the quests'
## content data.
static func _territory() -> TerritoryFeature:
	var content: QuestData = QuestContent.load_quests()
	if not content.problem.is_empty():
		push_error("the quests don't load: " + content.problem)
	for handed: PackedStringArray in content.handovers.values():
		if not exists(handed[0]):
			push_error("a territory quest hands over %s, which doesn't exist" % handed[0])
	return TerritoryFeature.new(content.handovers)


## The spikes' feature (#692) with every spikes' damage, by the code of its gear id, from the gear's
## content data. Gear that doesn't load is an error, and no spikes hurt then.
static func _spikes() -> SpikesFeature:
	var content: GearContent = GearContent.load_gear()
	if not content.problem.is_empty():
		push_error("the gear doesn't load: " + content.problem)
	var damages: Dictionary[int, int] = {}
	for item: GearItem in content.items.values():
		if item.damage > 0:
			damages[SpikesFeature.code_of(item.id)] = item.damage
	return SpikesFeature.new(damages)


## Every species' HP in the species `content`, by species id.
static func _max_hps(content: SpeciesData) -> Dictionary[String, int]:
	var max_hps: Dictionary[String, int] = {}
	for species_id: String in content.species:
		max_hps[species_id] = content.species[species_id].hp
	return max_hps


## The features that strike monsters, in their order: the type chart (#626), which doesn't step,
## the companions' auto attacks, and the specials (#410), with every species' special's power and
## cooldown, from the species `content` and the ability data. A special that doesn't load is an
## error, and its species has none.
static func _attacks(content: SpeciesData) -> Array[Feature]:
	var abilities: SpeciesData = SpeciesContent.load_abilities()
	if not abilities.problem.is_empty():
		push_error("the abilities don't load: " + abilities.problem)
	var powers: Dictionary[String, int] = {}
	var cooldowns: Dictionary[String, int] = {}
	var special_types: Dictionary[String, String] = {}
	for species_id: String in content.species:
		var special: Ability = abilities.abilities.get(content.species[species_id].special)
		if special == null or special.kind != Ability.SPECIAL:
			push_error("%s's special doesn't load" % species_id)
			continue
		powers[species_id] = special.power
		cooldowns[species_id] = special.cooldown_seconds * Simulation.TICKS_PER_SECOND
		special_types[species_id] = special.strike_type
	var attacks: Array[Feature] = [
		_type_chart(content, special_types),
		CompanionAttackFeature.new(),
		SpecialAttackFeature.new(powers, cooldowns),
	]
	return attacks


## The type chart's feature (#626) with every species' types and auto attack's type from the
## species `content`, and its special's type from `special_types`.
static func _type_chart(
	content: SpeciesData,
	special_types: Dictionary[String, String],
) -> TypeEffectivenessFeature:
	var types: Dictionary[String, PackedStringArray] = {}
	var auto_types: Dictionary[String, String] = {}
	for species_id: String in content.species:
		types[species_id] = PackedStringArray(content.species[species_id].types)
		auto_types[species_id] = content.species[species_id].strike_type
	return TypeEffectivenessFeature.new(types, auto_types, special_types)


## The wild monster feature with the named blueprint's species list and every species' stats from
## the species `content` (#219); when it didn't load, its monsters push on nothing.
static func _wild_monsters(instance_name: String, content: SpeciesData) -> WildMonsterFeature:
	var species: Dictionary[String, int] = blueprint(instance_name).wild_species
	var roster: Array[String] = []
	roster.assign(species.keys())
	var weights: Array[int] = []
	weights.assign(species.values())
	var strengths: Dictionary[String, int] = {}
	for species_id: String in content.species:
		strengths[species_id] = content.species[species_id].strength
	return WildMonsterFeature.new(roster, weights, strengths)


## The domination loot feature (#86) with every species loot table there is, and the harvest of
## felled wild monsters (#629) with every species' harvest table (#687), each with the blueprint's
## instance table for blanks, if it has one. Tables that don't load are an error; dominations and
## felled monsters then drop nothing.
static func _domination_loot(instance_name: String) -> DominationLootFeature:
	var tables: Dictionary[String, LootTable] = _species_tables(LootContent.DIR, LootTable.SPECIES)
	return DominationLootFeature.new(tables, _blank_table(instance_name))


static func _harvest(instance_name: String) -> HarvestFeature:
	var tables: Dictionary[String, LootTable] = _species_tables(
		LootContent.HARVEST_DIR,
		LootTable.HARVEST,
	)
	return HarvestFeature.new(tables, _blank_table(instance_name))


## Every table of `kind` in `directory`, by its id, which is its species' id.
static func _species_tables(directory: String, kind: String) -> Dictionary[String, LootTable]:
	var content: LootData = LootContent.load_loot_tables(directory)
	if not content.problem.is_empty():
		push_error("the loot tables don't load: " + content.problem)
	var species_tables: Dictionary[String, LootTable] = {}
	for table: LootTable in content.loot_tables.values():
		if table.kind == kind:
			species_tables[table.id] = table
	return species_tables


## The named blueprint's instance loot table, which a species table's blank rolls on, or null.
static func _blank_table(instance_name: String) -> LootTable:
	var table_id: String = blueprint(instance_name).loot_table
	return null if table_id.is_empty() else _loot_table(table_id, LootTable.INSTANCE)


## The named blueprint's chest loot table, which its chests hold, or null.
static func _chest_table(instance_name: String) -> LootTable:
	return _loot_table(blueprint(instance_name).chest_table, LootTable.CHEST)


## The loot table with this id and `kind`, or null when the tables don't load or it isn't one.
static func _loot_table(table_id: String, kind: String) -> LootTable:
	var content: LootData = LootContent.load_loot_tables()
	var table: LootTable = content.loot_tables.get(table_id)
	if not content.problem.is_empty() or table == null or table.kind != kind:
		return null
	return table


## The region piece in the file at `path`, every tile of it named after the file (#350).
static func _piece(path: String) -> Region:
	var piece: Region = read_region(FileAccess.get_file_as_string(path))
	if not piece.problem.is_empty():
		piece.problem = "%s: %s" % [path, piece.problem]
	var piece_id: String = path.get_file().get_basename()
	for tile: Vector2i in piece.terrain:
		piece.piece_of[tile] = piece_id
	return piece


## The blueprints' content data, read on first use; blueprints that don't load are an error, and
## there are none then.
static func _loaded() -> BlueprintContent:
	if _content == null:
		_content = BlueprintContent.load_blueprints()
		if not _content.problem.is_empty():
			push_error("the instance blueprints don't load: " + _content.problem)
			_content.blueprints.clear()
	return _content
