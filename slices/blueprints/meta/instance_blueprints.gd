class_name InstanceBlueprints
extends RefCounted
## Instance blueprints (#117): what an instance is loaded from, by name. A blueprint is a region and
## the features an instance has, in their step order. The region is a fixed region file,
## regions/<name>.md, or region pieces in regions/<name>/ that the seed arranges and, unless the
## blueprint keeps its layout, turns (#57, #127). The players start on the region's starts. A
## blueprint switches game rules on and off by listing them, and they can change during a session.
## One with a chest loot table has treasure chests too, rolling on it (#124, #694), and the loot on
## its ground rolls on its instance loot table (#90, #203).

## The playground: the hand-made region regions/basic.md, walking, each player's companion (#338)
## with its attacks and swapping it for another carried monster (#55), a trail per player, the wild
## monsters the region places, dominating them with a ring, and fog of war. Only the tests play it
## (#712): no exit leads to it, so they load it directly.
const BASIC: String = "basic"
## The load test's (#101): a big region full of wild monsters, the same rules as every instance.
const LOAD: String = "load"
## The first region arranged from region pieces (#57): a glade the seed puts together, where the
## world starts (#712).
const GLADE: String = "glade"
## A boss-style arena (#127): one region piece that is never turned, so it plays as it is drawn.
const ARENA: String = "arena"
## Room for the upcoming features (#689), each arranged from five large region pieces in a line,
## joined across whole edges: a forest north of the glade, with trees and rock to harvest later
## (#675); the ruined castle west of the forest, to be corrupted (#574); a faction outpost southeast
## of the glade, with holds for control points (#643); and the mountain pass southwest of the
## outpost, with a sealed side passage for a hidden gate (#500).
const FOREST: String = "forest"
const CASTLE: String = "castle"
const OUTPOST: String = "outpost"
const MOUNTAIN_PASS: String = "mountain_pass"
const NAMES: Array[String] = [BASIC, LOAD, GLADE, ARENA, FOREST, CASTLE, OUTPOST, MOUNTAIN_PASS]
## The corrupted glade (#541): the flag that corrupts the glade, and the variant it chooses, a
## placeholder region until the corrupted instances' own arrive. Its corrupting monster emits
## GLADE_PURIFIED when it faints (regions/glade_corrupted.md), whose flag purifies it.
const CORRUPTED_GLADE: String = "glade_corrupted"
const GLADE_PURIFIED: String = "glade_purified"
## The blueprints whose region pieces keep the layout they're drawn in: the seed doesn't turn them.
## Every instance in the web of exits is one, so an exit always leads out the same way (#120).
const UNTURNED: Array[String] = [GLADE, ARENA, FOREST, CASTLE, OUTPOST, MOUNTAIN_PASS]
## Each blueprint's instance loot table (the loot slice's data/loot_tables/), by blueprint: what a
## blank and the loot on its ground give.
const LOOT_TABLES: Dictionary[String, String] = { GLADE: "glade" }
## Each blueprint's chest loot table (the loot slice's data/loot_tables/), by blueprint: what its
## chests hold (#694). Every one also has an instance loot table, for the loot on its ground.
const CHEST_TABLES: Dictionary[String, String] = { GLADE: "glade_chest" }
## Which species live in each blueprint, and how likely each is, for the wild monster spots its
## region doesn't name (#133): species id to weight.
const WILD_SPECIES: Dictionary[String, Dictionary] = {
	BASIC: { "ombulumo": 3, "tikazzir": 1 },
	LOAD: { "ombulumo": 1, "tikazzir": 1 },
	GLADE: { "ombulumo": 1 },
	ARENA: { "ombulumo": 1 },
	FOREST: { "ombulumo": 2, "tikazzir": 1 },
	CASTLE: { "ombulumo": 1, "tikazzir": 1 },
	OUTPOST: { "ombulumo": 1, "tikazzir": 1 },
	MOUNTAIN_PASS: { "ombulumo": 1, "tikazzir": 2 },
}
## Each blueprint's variants (#529), by blueprint: world flag to the variant it chooses, the first
## of its flags in the order listed that the world has set choosing (#541), so a later story beat
## listed first overrides an earlier one. A variant is named after its own region in REGIONS, a
## region file or a folder of region pieces like a blueprint's, which it is loaded with instead; the
## rest of the blueprint stays. "" is the blueprint's own region: the glade, once its corruption's
## event was emitted, is purified, the glade again.
const VARIANTS: Dictionary[String, Dictionary] = {
	GLADE: {
		WorldFlags.EVENT_FLAG + GLADE_PURIFIED: "",
		CORRUPTED_GLADE: CORRUPTED_GLADE,
	},
}
const REGIONS: String = "res://regions/"
## The region piece an arranged region starts from, holding the players' starts.
const START_PIECE: String = "start.md"


## Whether a blueprint of this name exists.
static func exists(instance_name: String) -> bool:
	return NAMES.has(instance_name)


## The variant of the named blueprint that the world's `flags` choose (VARIANTS), or "".
static func variant(instance_name: String, flags: Array[String]) -> String:
	var chosen_by: Dictionary = VARIANTS.get(instance_name, { })
	# A const dictionary keeps the order it's written in, the same on every platform.
	for flag: Variant in chosen_by:
		if flags.has(str(flag)):
			return str(chosen_by[flag])
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
	if CHEST_TABLES.has(instance_name):
		var chest_table: LootTable = _loot_table(CHEST_TABLES[instance_name], LootTable.CHEST)
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
	# After the specials, whose strikes fell the wild monsters it drops materials for.
	ordered.append(_harvest(instance_name))
	ordered.append_array([_health(species), _dialogs(), _territory()])
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
	if not region.npcs.is_empty():
		features.append(NpcFeature.new())
	return features


## The named blueprint's region for `seed_value`, from its `variant_name`'s region (#529) or, for
## "", its own: the region file as it is, or its region pieces arranged, the start piece first and
## the others by file name, and turned unless the blueprint is UNTURNED. Its `problem` says what's
## wrong.
static func region_of(instance_name: String, seed_value: int, variant_name: String = "") -> Region:
	var region_name: String = variant_name if not variant_name.is_empty() else instance_name
	var path: String = REGIONS + region_name + ".md"
	if FileAccess.file_exists(path):
		return RegionDocument.parse(FileAccess.get_file_as_string(path))
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
	return RegionArranger.arrange(pieces, seed_value, not UNTURNED.has(instance_name))


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


## The health feature (#455) with every species' HP, from the species `content`, for companions.
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
	var species: Dictionary = WILD_SPECIES.get(instance_name, { })
	var roster: Array[String] = []
	var weights: Array[int] = []
	for species_id: Variant in species:
		var weight: int = species[species_id]
		roster.append(str(species_id))
		weights.append(weight)
	var strengths: Dictionary[String, int] = {}
	for species_id: String in content.species:
		strengths[species_id] = content.species[species_id].strength
	return WildMonsterFeature.new(roster, weights, _max_hps(content), strengths)


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
	if not LOOT_TABLES.has(instance_name):
		return null
	return _loot_table(LOOT_TABLES[instance_name], LootTable.INSTANCE)


## The loot table with this id and `kind`, or null when the tables don't load or it isn't one.
static func _loot_table(table_id: String, kind: String) -> LootTable:
	var content: LootData = LootContent.load_loot_tables()
	var table: LootTable = content.loot_tables.get(table_id)
	if not content.problem.is_empty() or table == null or table.kind != kind:
		return null
	return table


## The region piece in the file at `path`, every tile of it named after the file (#350).
static func _piece(path: String) -> Region:
	var piece: Region = RegionDocument.parse(FileAccess.get_file_as_string(path))
	if not piece.problem.is_empty():
		piece.problem = "%s: %s" % [path, piece.problem]
	var piece_id: String = path.get_file().get_basename()
	for tile: Vector2i in piece.terrain:
		piece.piece_of[tile] = piece_id
	return piece
