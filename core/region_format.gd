class_name RegionFormat
extends RefCounted
## Reading a region in its compact text form (#36, #145) into a Region: the rows of the grid and the
## keyed lines that place kinds, connectors, exits, species, triggers and loot on it. Region holds
## the region's data and its geometry; this reads the format, which RegionDocument writes from a
## region file.

## The characters of a region file, by terrain; a digit 1 to 4 is ground where that player starts.
const SYMBOLS: Dictionary[String, int] = {
	".": Region.GROUND,
	"~": Region.WATER,
	"^": Region.BLOCKED,
}
## Ground where a wild monster stands when the instance loads (WildMonsterFeature, #19).
const WILD_MONSTER: String = "m"
## Ground where a treasure chest stands, placed by hand (ChestFeature, #124).
const CHEST: String = "c"
## The start of a region piece's connector line.
const CONNECTOR: String = "connector "
## The start of a region piece's exit line (#140).
const EXIT: String = "exit "
## The start of a line naming a wild monster spot's species (#133).
const SPECIES: String = "species "
## A species line's last word for a wild monster that starts wounded (#389).
const WOUNDED: String = "wounded"
## A species line's word naming the event its wild monster emits when it faints (#541):
## `emits=<event name>`.
const EMITS: String = "emits="
## A species line's word naming the quest target its wild monster is (#625): `target=<id>`, an id
## like a place's (TileTrigger.is_place_id).
const TARGET: String = "target="
## The start of a tile trigger's line (#181, #183).
const TRIGGER: String = "trigger "
## The start of a line standing a person on a tile (#557): `npc <q> <r> <npc id> [<dialog id>]`.
const NPC: String = "npc "
## The start of a line placing loot on the ground on a tile (#203).
const LOOT: String = "loot "
## The start of a line placing a tile blueprint on a tile (#116).
const TILE: String = "tile "
## What a tile line says to override its kind's walkable trait for that one tile (#201).
const WALKABLE: String = "walkable"
const NOT_WALKABLE: String = "not_walkable"
## A tile line's height override (#232): `height=<n>`, in hundredths of a tile's radius, up to
## MAX_HEIGHT, so a typo can't make one tile block every crown.
const HEIGHT: String = "height="
const MAX_HEIGHT: int = 1000


## A region read from a region file's text. Lines starting with `#` are comments. The first other
## line is `origin <column> <row>`: the character there is tile (0, 0). Every further line is one
## row r of the region, from the origin row's r = 0 down; a tile sits on every second column
## (doubled coordinates), so each row is offset by half a tile, as on screen. `.` is ground, `~`
## water, `^` blocked, a digit 1 to 4 a player's start on ground, `m` a wild monster on ground, `c`
## a treasure chest on ground, and a space no tile. A region piece adds a line `connector <q> <r>
## <side>` for each connector, `exit <q> <r> <side> <blueprint>` for each exit, `species <q> <r>
## <species id>` for a wild monster spot whose species it names, and `trigger <q> <r> <when>
## <action> <amount>` for each tile trigger (`<place id>` for the amount of one that marks a
## place), and `npc <q> <r> <npc id> [<dialog id>]` for each person standing there. A line
## `tile <q> <r> <tile blueprint id>` makes a
## tile of the grid that kind, before the other lines are read.
static func parse(text: String) -> Region:
	var region: Region = Region.new()
	var rows: Array[String] = []
	var connector_lines: Array[String] = []
	var tile_lines: Array[String] = []
	for line: String in text.split("\n"):
		var content: String = line.strip_edges()
		var keyed: bool = (content.begins_with(EXIT) or content.begins_with(SPECIES)
				or content.begins_with(TRIGGER) or content.begins_with(LOOT)
				or content.begins_with(NPC))
		if content.begins_with(TILE):
			tile_lines.append(content)
		elif content.begins_with(CONNECTOR) or keyed:
			connector_lines.append(content)
		elif not content.begins_with("#") and not content.is_empty():
			rows.append(line.trim_suffix("\r"))
	var header: PackedStringArray = PackedStringArray()
	if not rows.is_empty():
		header = rows[0].split(" ")
	var numbers: bool = header.size() == 3 and header[1].is_valid_int() and header[2].is_valid_int()
	if not numbers or header[0] != "origin":
		region.problem = "a region file starts with \"origin <column> <row>\""
		return region
	var starts_by_slot: Dictionary[int, Vector2i] = {}
	for i: int in range(1, rows.size()):
		region.problem = _parse_row(
			region,
			rows[i],
			i - 1 - header[2].to_int(),
			header[1].to_int(),
			starts_by_slot,
		)
		if not region.problem.is_empty():
			return region
	for slot: int in starts_by_slot.size():
		if not starts_by_slot.has(slot):
			region.problem = "the player starts aren't numbered 1, 2, 3, … without gaps"
			return region
		region.starts.append(starts_by_slot[slot])
	for line: String in tile_lines + connector_lines:
		region.problem = _parse_keyed(region, line)
		if not region.problem.is_empty():
			return region
	return region


## Reads one `connector <q> <r> <side>` or `exit <q> <r> <side> <blueprint>` line; returns why it
## can't, or "". Both sit on a ground tile and open to a side where the piece has no tile.
static func _parse_connector(region: Region, line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var exit: bool = line.begins_with(EXIT)
	var numbers: bool = parts.size() == (5 if exit else 4)
	for part: String in parts.slice(1, 4):
		numbers = numbers and part.is_valid_int()
	if not numbers:
		if exit:
			return "an exit line reads \"exit <q> <r> <side> <blueprint>\": " + line
		return "a connector line reads \"connector <q> <r> <side>\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	var side: int = parts[3].to_int()
	if side < 0 or side >= Hex.DIRECTIONS.size():
		return "%s side %d isn't 0 to 5" % [parts[0], side]
	if not region.is_walkable(tile) or region.has_tile(tile + Hex.DIRECTIONS[side]):
		return "%s %s doesn't open from ground to the edge on side %d" % [parts[0], tile, side]
	if exit:
		region.exits.append(Vector3i(tile.x, tile.y, side))
		region.exit_blueprints.append(parts[4])
	else:
		region.connectors.append(Vector3i(tile.x, tile.y, side))
	return ""


## Reads one keyed line: a tile's kind, a connector, an exit, a named species, a trigger, loot or
## a person.
## Returns why it can't, or "".
static func _parse_keyed(region: Region, line: String) -> String:
	if line.begins_with(TILE):
		return _parse_tile(region, line)
	if line.begins_with(SPECIES):
		return _parse_species(region, line)
	if line.begins_with(TRIGGER):
		return _parse_trigger(region, line)
	if line.begins_with(LOOT):
		return _parse_loot(region, line)
	if line.begins_with(NPC):
		return _parse_npc(region, line)
	return _parse_connector(region, line)


## Reads one `loot <q> <r>` line; returns why it can't, or "". Loot lies on ground, once a tile.
static func _parse_loot(region: Region, line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return "a loot line reads \"loot <q> <r>\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	if not region.is_walkable(tile) or region.loot_spots.has(tile) or region.chests.has(tile):
		return "loot on %s isn't on free ground" % tile
	region.loot_spots.append(tile)
	return ""


## Reads one `npc <q> <r> <npc id> [<dialog id>]` line; returns why it can't, or "". A person
## stands on ground nothing else stands on (no player's start, wild monster, chest or loot), once,
## and both ids are identifiers.
static func _parse_npc(region: Region, line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var sized: bool = parts.size() == 4 or parts.size() == 5
	if not sized or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return "an npc line reads \"npc <q> <r> <npc id> [<dialog id>]\": " + line
	var dialog: String = parts[4] if parts.size() == 5 else ""
	var named: bool = parts[3].is_valid_ascii_identifier()
	if not named or not (dialog.is_empty() or dialog.is_valid_ascii_identifier()):
		return "an npc's id and dialog are identifiers: " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	var taken: bool = (region.starts.has(tile) or region.wild_monsters.has(tile)
			or region.chests.has(tile) or region.loot_spots.has(tile) or region.npcs.has(tile))
	if not region.is_walkable(tile) or taken:
		return "npc on %s isn't on free ground" % tile
	region.npcs[tile] = NpcSpot.new(parts[3], dialog)
	return ""


## Reads one `trigger <q> <r> <when> <action> <amount>` line; returns why it can't, or "". A
## trigger stands on ground, with a when and an action TileTrigger knows and an amount of at least
## 1; a REACH trigger names its place's id in the amount's stead (#339).
static func _parse_trigger(region: Region, line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var numbers: bool = parts.size() == 6
	for i: int in [1, 2]:
		numbers = numbers and parts.size() > i and parts[i].is_valid_int()
	if not numbers:
		return "a trigger line reads \"trigger <q> <r> <when> <action> <amount>\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	if not TileTrigger.WHENS.has(parts[3]) or not TileTrigger.ACTIONS.has(parts[4]):
		return "trigger %s: no such when or action: %s %s" % [tile, parts[3], parts[4]]
	var place: String = parts[5] if parts[4] == TileTrigger.REACH else ""
	var amount: int = parts[5].to_int() if parts[5].is_valid_int() and place.is_empty() else 0
	var acts: bool = amount >= 1 or TileTrigger.is_place_id(place)
	if not region.is_walkable(tile) or not acts:
		return "trigger %s isn't on ground or acts on nothing" % tile
	region.triggers.append(TileTrigger.new(tile, parts[3], parts[4], amount, place))
	return ""


## Reads one `tile <q> <r> <tile blueprint id> [<turn>] [walkable | not_walkable]` line; returns
## why it can't, or "". It gives a tile of the grid its kind, its decoration a turn of 0 to 5
## sixths if it names one (#231), and overrides its kind's walkable trait for this tile if it says
## so (#201).
static func _parse_tile(region: Region, line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.size() < 4 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return "a tile line reads \"tile <q> <r> <tile blueprint id> [<turn>] [walkable]\": " + line
	var tile: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	var kind: int = TileKinds.number_of(parts[3])
	if not region.has_tile(tile) or kind < 0:
		return "tile %s isn't on the region, or %s isn't a tile blueprint" % [tile, parts[3]]
	region.terrain[tile] = kind
	var extras: PackedStringArray = parts.slice(4)
	# At most a turn and one override, each said once.
	var turns_said: int = 0
	for extra: String in extras:
		turns_said += 1 if extra.is_valid_int() else 0
	var overrides_said: int = extras.count(WALKABLE) + extras.count(NOT_WALKABLE)
	var heights_said: int = 0
	for extra: String in extras:
		heights_said += 1 if extra.begins_with(HEIGHT) else 0
	if turns_said > 1 or overrides_said > 1 or heights_said > 1:
		return "tile %s says its turn or its walkable trait twice: %s" % [tile, line]
	for extra: String in extras:
		var wrong: String = _parse_tile_extra(region, tile, extra)
		if not wrong.is_empty():
			return wrong
	return ""


## Reads what a tile line says after the tile's kind: its decoration's turn, or an override of its
## walkable trait. Returns why it can't, or "".
static func _parse_tile_extra(region: Region, tile: Vector2i, extra: String) -> String:
	if extra.is_valid_int():
		var turn: int = extra.to_int()
		if turn < 0 or turn >= Hex.DIRECTIONS.size():
			return "tile %s's turn %d isn't 0 to 5" % [tile, turn]
		if turn != 0:
			region.looks.decoration_turns[tile] = turn
	elif extra == WALKABLE or extra == NOT_WALKABLE:
		region.walkable_overrides[tile] = extra == WALKABLE
	elif extra.begins_with(HEIGHT) and extra.trim_prefix(HEIGHT).is_valid_int():
		var height: int = extra.trim_prefix(HEIGHT).to_int()
		if height < 0 or height > MAX_HEIGHT:
			return "tile %s's height %d isn't 0 to %d" % [tile, height, MAX_HEIGHT]
		region.looks.height_overrides[tile] = height
	else:
		return "tile %s: %s is neither a turn nor %s or %s" % [tile, extra, WALKABLE, NOT_WALKABLE]
	return ""


## Reads one `species <q> <r> <species id> [wounded] [emits=<event name>] [target=<id>]` line;
## returns why it can't, or "". It names the species of a wild monster spot, once, the event its
## monster emits when it faints (#541), an identifier, and the quest target it is (#625), an id
## no other spot of the region has.
static func _parse_species(region: Region, line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	var extras: PackedStringArray = parts.slice(4)
	var wounded: bool = extras.has(WOUNDED)
	var emits: String = _extra(extras, EMITS)
	var target: String = _extra(extras, TARGET)
	var understood: bool = emits.is_valid_ascii_identifier() or emits.is_empty()
	understood = understood and (TileTrigger.is_place_id(target) or target.is_empty())
	var named: int = int(wounded) + int(not emits.is_empty()) + int(not target.is_empty())
	understood = understood and extras.size() == named
	var sized: bool = parts.size() >= 4 and understood
	if not sized or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		var form: String = "species <q> <r> <species id> [wounded] [emits=<event>] [target=<id>]"
		return "a species line reads \"%s\": %s" % [form, line]
	var spot: Vector2i = Vector2i(parts[1].to_int(), parts[2].to_int())
	if not region.wild_monsters.has(spot) or region.wild_spots.has(spot):
		return "species %s names no wild monster spot, or one named before" % spot
	for other: WildSpot in region.wild_spots.values():
		if not target.is_empty() and other.target == target:
			return "species %s: the quest target %s is one monster, marked once" % [spot, target]
	region.wild_spots[spot] = WildSpot.new(parts[3], wounded, emits, target)
	return ""


## What the one extra of `extras` starting with `key` names after it, or "" when none or several
## do.
static func _extra(extras: PackedStringArray, key: String) -> String:
	var found: String = ""
	for extra: String in extras:
		if extra.begins_with(key):
			if not found.is_empty():
				return ""
			found = extra.trim_prefix(key)
	return found


## Reads one row of a region file into the region; returns why it can't, or "".
static func _parse_row(
	region: Region,
	row: String,
	r: int,
	origin_column: int,
	starts_by_slot: Dictionary[int, Vector2i],
) -> String:
	for column: int in row.length():
		var symbol: String = row[column]
		if symbol == " ":
			continue
		# Doubled coordinates: column = 2q + r, counted from the origin's column.
		var doubled: int = column - origin_column - r
		var slot: int = symbol.to_int() - 1 if symbol.is_valid_int() else -1
		if posmod(doubled, 2) != 0:
			return "'%s' in row %d sits between two tiles" % [symbol, r]
		var known: bool = SYMBOLS.has(symbol) or symbol in [WILD_MONSTER, CHEST]
		if not known and (slot < 0 or slot >= GameState.MAX_PLAYERS):
			return "'%s' in row %d isn't a region symbol" % [symbol, r]
		var tile: Vector2i = Vector2i(Fixed.div_floor(doubled, 2), r)
		region.terrain[tile] = SYMBOLS.get(symbol, Region.GROUND)
		if symbol == WILD_MONSTER:
			region.wild_monsters.append(tile)
		if symbol == CHEST:
			region.chests.append(tile)
		if slot >= 0 and starts_by_slot.has(slot):
			return "player %d's start is marked twice" % (slot + 1)
		if slot >= 0:
			starts_by_slot[slot] = tile
	if region.terrain.size() > Region.MAX_TILES:
		return "the region has more than %d tiles" % Region.MAX_TILES
	return ""
