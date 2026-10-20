class_name LegendMeaning
extends RefCounted
## What one symbol of a region document's legend stands for (#145), read from its meaning, and how
## it builds that onto the tiles it's drawn on: RegionDocument reads the document and builds its
## Region with these (#824). A meaning is one of:
## - `ground`, `water` or `rock`, `where player <n> starts` (on ground) or `a wild monster, of a
##   species rolled from the instance blueprint's list` (on ground)
## - what a slice places on ground, as its PlacementReader reads it (#824): a person to talk to
##   (NpcSpot), a treasure chest or loot on the ground (ChestPlacements)
## - `joins another piece to the <side>`: a connector (#57)
## - `exit to the <side>, to <blueprint>`: an exit to another instance (#140)
## - `a wild monster, always <species id>`: a wild monster of a named species (#133); with
##   `, wounded` after it, it starts at a low share of its HP (#389); with
##   `, emitting <event name>` next, it emits that event when it faints (#541, EventEmitted); with
##   `, the quest target <id>` next, it's the one monster a quest's step asks for by that id
##   (#625, like a place's); with `, on <tile kind's meaning>` last, it stands on a tile of that
##   kind rather than on ground (#452),
##   e.g. `a wild monster, always ombulumo, wounded, on sand` or
##   `a wild monster, always ombulumo, the quest target old_toad`
## - `a wild monster hiding in <tile blueprint id>`: a wild monster, of a species rolled from the
##   instance blueprint's list, on a tile of that kind, which must hide (#202), e.g. `a wild monster
##   hiding in shrubs`
## - `<what it is>; <when> <action>`: a tile trigger (#183), e.g. `a lookout; stepping here reveals
##   within 8`, with TileTrigger's whens and actions in words: `stepping here`,
##   `reveals within <n>`, `reaches the place <place id>` (#339: every tile of a place has it, e.g.
##   `the beach; stepping here reaches the place beach`). When what it is is a tile kind's meaning
##   (below), the tile is that kind too (#349), e.g. `forest; stepping here reaches the place grove`
## - `<tile blueprint id>`: a tile of that kind (#116), e.g. `forest`. Clauses after the kind, each
##   after a ", ", change that tile: `turned <n>` turns its decoration by n sixths of a turn,
##   counter-clockwise (#231), so two symbols can stand for the same kind turned apart, and
##   `walkable` or `not walkable` overrides its kind's trait for this tile (#201), e.g. `forest, not
##   walkable`, and `height <n>` sets how tall it stands for crowns above it (#232), in hundredths
##   of a tile's radius, where its models' measured height doesn't fit, e.g. `shrubs, height 40`
## where <side> is one of SIDES. Every symbol but water and rock is ground unless it names a kind.

## The built-in terrains' meanings.
const TERRAINS: Dictionary[String, int] = {
	"ground": Region.GROUND,
	"water": Region.WATER,
	"rock": Region.BLOCKED,
}
## A player's start's meaning, with the player's number (1 to GameState.MAX_PLAYERS).
const START: String = "where player %d starts"
## A wild monster's meaning whose species is rolled from its blueprint's list (WildMonsterFeature,
## #19).
const ROLLED: String = "a wild monster, of a species rolled from the instance blueprint's list"
const CONNECTOR: String = "joins another piece to the "
## An exit's meaning, before its side and, after TO, its blueprint.
const EXIT: String = "exit to the "
const TO: String = ", to "
## A legend meaning placing a wild monster in a tile that hides it (#202), before the tile's kind.
const HIDING: String = "a wild monster hiding in "
## How a named wild monster's legend meaning begins, and the clauses that may follow its species,
## each once: its wounding, the event it emits when it faints (#541), the quest target it is
## (#625), and, last, the tile kind it stands on (#452).
const NAMED: String = "a wild monster, always "
const WOUNDED: String = "wounded"
const EMITTING: String = "emitting "
const TARGETED: String = "the quest target "
const ON: String = "on "
## What separates what a trigger's tile is from its when and action.
const TRIGGER: String = "; "
## A trigger's when and actions in words, each with TileTrigger's own.
const WHENS: Dictionary[String, String] = { "stepping here ": TileTrigger.STEP }
const ACTIONS: Dictionary[String, String] = {
	"reveals within ": TileTrigger.REVEAL,
	"reaches the place ": TileTrigger.REACH,
}
## The sides of a tile, in Hex.DIRECTIONS' order.
const SIDES: Array[String] = ["east", "northeast", "northwest", "west", "southwest", "southeast"]
## What a tile kind's legend meaning says, after the kind, to turn its decoration (#231), to
## override its walkable trait (#201) or to set its height (#232), each clause after a ", ".
const TURNED: String = "turned "
const WALKABLE: String = "walkable"
const NOT_WALKABLE: String = "not walkable"
const HEIGHT: String = "height "

## The tile's terrain, before a kind it names.
var terrain: int = Region.GROUND
## The player slot starting here, or -1.
var start: int = -1
var wild_monster: bool = false
## The kind of thing a slice places here (#824, PlacementReader), or "", and the meaning it reads.
var placement: String = ""
var meaning_said: String = ""
## The tile kind (TileKinds' number) it names, or -1, with each turn, walkable override and height
## its clauses say, refused when one is said twice or is out of range.
var kind: int = -1
var turns: Array[int] = []
var walkable_overrides: Array[bool] = []
var heights: Array[int] = []
## What it names about its wild monster (#133), or null.
var wild_spot: WildSpot = null
## The side a connector or exit opens to, or -1, and the blueprint an exit leads to.
var connector_side: int = -1
var exit_side: int = -1
var exit_blueprint: String = ""
## Its tile trigger (#183), on tile (0, 0), or null.
var trigger: TileTrigger = null


## What `meaning` stands for, or null when it isn't understood; `readers` read what the slices
## place.
static func read(meaning: String, readers: Array[PlacementReader]) -> LegendMeaning:
	var read_one: LegendMeaning = LegendMeaning.new()
	var understood: bool = false
	if meaning.begins_with(NAMED):
		understood = read_one._read_named(meaning.trim_prefix(NAMED))
	elif meaning.contains(TRIGGER):
		understood = read_one._read_trigger(meaning)
	else:
		understood = (read_one._read_placed(meaning)
				or read_one._read_slices(meaning, readers)
				or read_one._read_kind(meaning))
	return read_one if understood else null


## Builds what lies on `tile` itself: its terrain, its kind with its clauses, and a wild monster
## on it. Returns why it can't, or "".
func lay(region: Region, tile: Vector2i) -> String:
	region.terrain[tile] = terrain
	if wild_monster:
		region.wild_monsters.append(tile)
	if kind < 0:
		return ""
	region.terrain[tile] = kind
	if turns.size() > 1 or walkable_overrides.size() > 1 or heights.size() > 1:
		return "tile %s says its turn or its walkable trait twice" % tile
	for turn: int in turns:
		if turn < 0 or turn >= Hex.DIRECTIONS.size():
			return "tile %s's turn %d isn't 0 to 5" % [tile, turn]
		if turn != 0:
			region.looks.decoration_turns[tile] = turn
	for walkable: bool in walkable_overrides:
		region.walkable_overrides[tile] = walkable
	for height: int in heights:
		if height < 0 or height > PieceLooks.MAX_HEIGHT:
			return "tile %s's height %d isn't 0 to %d" % [tile, height, PieceLooks.MAX_HEIGHT]
		region.looks.height_overrides[tile] = height
	return ""


## Places what stands on `tile` or leads off it, once every tile is laid: a connector or exit,
## which open from ground to the edge, a named wild monster, a trigger, or what a slice places.
## Returns why it can't, or "".
func place(region: Region, tile: Vector2i) -> String:
	var side: int = maxi(connector_side, exit_side)
	if side >= 0:
		var what: String = "connector" if connector_side >= 0 else "exit"
		if not region.is_walkable(tile) or region.has_tile(tile + Hex.DIRECTIONS[side]):
			return "%s %s doesn't open from ground to the edge on side %d" % [what, tile, side]
		if connector_side >= 0:
			region.connectors.append(Vector3i(tile.x, tile.y, side))
		else:
			region.exits.append(Vector3i(tile.x, tile.y, side))
			region.exit_blueprints.append(exit_blueprint)
	if wild_spot != null:
		for other: WildSpot in region.wild_spots.values():
			if not wild_spot.target.is_empty() and other.target == wild_spot.target:
				return "species %s: the quest target %s is one monster, marked once" % [
					tile,
					wild_spot.target,
				]
		region.wild_spots[tile] = wild_spot
	if trigger != null:
		var acts: bool = trigger.amount >= 1 or not trigger.place.is_empty()
		if not region.is_walkable(tile) or not acts:
			return "trigger %s isn't on ground or acts on nothing" % tile
		region.triggers.append(trigger.moved(tile))
	return _place_on_ground(region, tile)


## Places what a slice places on `tile`, which must be ground. Returns why it can't, or "".
func _place_on_ground(region: Region, tile: Vector2i) -> String:
	if placement.is_empty():
		return ""
	if not region.is_walkable(tile):
		return "%s on %s isn't on ground" % [placement, tile]
	region.add_placement(placement, tile, meaning_said)
	return ""


## Reads a named wild monster's meaning after NAMED (`ombulumo, wounded, on sand`); returns whether
## it could.
func _read_named(named: String) -> bool:
	var clauses: PackedStringArray = named.split(", ")
	var species: String = clauses[0]
	var wounded: bool = false
	var emits: String = ""
	var target: String = ""
	for i: int in range(1, clauses.size()):
		var clause: String = clauses[i]
		if clause.begins_with(ON):
			if not _read_kind(", ".join(clauses.slice(i)).trim_prefix(ON)):
				return false
			break
		var emitted: String = clause.trim_prefix(EMITTING)
		var targeted: String = clause.trim_prefix(TARGETED)
		if clause == WOUNDED and not wounded:
			wounded = true
		elif (clause.begins_with(EMITTING)
				and emits.is_empty()
				and emitted.is_valid_ascii_identifier()):
			emits = emitted
		elif (clause.begins_with(TARGETED)
				and target.is_empty()
				and TileTrigger.is_place_id(targeted)):
			target = targeted
		else:
			return false
	if not species.is_valid_ascii_identifier():
		return false
	wild_monster = true
	wild_spot = WildSpot.new(species, wounded, emits, target)
	return true


## Reads a trigger's meaning (`a lookout; stepping here reveals within 8`), whose tile is a kind
## when what it is names one (#349); returns whether it could.
func _read_trigger(meaning: String) -> bool:
	var what: String = meaning.get_slice(TRIGGER, 0)
	var clause: String = meaning.get_slice(TRIGGER, 1)
	if what.strip_edges().is_empty():
		return false
	for phrase: String in WHENS:
		var rest: String = clause.trim_prefix(phrase)
		for action: String in ACTIONS:
			var amount: String = rest.trim_prefix(action)
			var reach: bool = ACTIONS[action] == TileTrigger.REACH
			var known: bool = TileTrigger.is_place_id(amount) if reach else amount.is_valid_int()
			if clause.begins_with(phrase) and rest.begins_with(action) and known:
				var _kind_named: bool = _read_kind(what)
				return _set_trigger(WHENS[phrase], ACTIONS[action], amount)
	return false


## Sets the trigger to fire `when` and do `action` by `amount`: how far, or a REACH trigger's place.
## Returns true.
func _set_trigger(when: String, action: String, amount: String) -> bool:
	var reach: bool = action == TileTrigger.REACH
	var place_id: String = amount if reach else ""
	trigger = TileTrigger.new(
		Vector2i.ZERO,
		when,
		action,
		0 if reach else amount.to_int(),
		place_id,
	)
	return true


## Reads a meaning built in, or one placing something on ground: a connector, an exit or a wild
## monster hiding in a tile kind. Returns whether it could.
func _read_placed(meaning: String) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		start = slot if meaning == START % (slot + 1) else start
	wild_monster = meaning == ROLLED
	terrain = TERRAINS.get(meaning, Region.GROUND)
	if start >= 0 or wild_monster or TERRAINS.has(meaning):
		return true
	if meaning.begins_with(CONNECTOR):
		connector_side = SIDES.find(meaning.trim_prefix(CONNECTOR))
		return connector_side >= 0
	if meaning.begins_with(EXIT):
		var exit: PackedStringArray = meaning.trim_prefix(EXIT).split(TO)
		if exit.size() != 2 or not exit[1].is_valid_ascii_identifier():
			return false
		exit_side = SIDES.find(exit[0])
		exit_blueprint = exit[1]
		return exit_side >= 0
	var hides_in: int = TileKinds.number_of(meaning.trim_prefix(HIDING))
	if meaning.begins_with(HIDING) and TileKinds.hides(hides_in):
		wild_monster = true
		kind = hides_in
		return true
	return false


## Reads a meaning one of `readers` knows, placing something of a slice's on ground (#824); returns
## whether one did.
func _read_slices(meaning: String, readers: Array[PlacementReader]) -> bool:
	for reader: PlacementReader in readers:
		placement = reader.kind_of(meaning)
		if not placement.is_empty():
			meaning_said = meaning
			return true
	return false


## Reads a tile kind's meaning (`stump`, or `stump, turned 3, not walkable`); returns whether it
## could, and leaves the kind unset when it couldn't.
func _read_kind(meaning: String) -> bool:
	var clauses: PackedStringArray = meaning.split(", ")
	var said_turns: Array[int] = []
	var said_overrides: Array[bool] = []
	var said_heights: Array[int] = []
	for clause: String in clauses.slice(1):
		var turn: String = clause.trim_prefix(TURNED)
		var height: String = clause.trim_prefix(HEIGHT)
		if clause.begins_with(TURNED) and turn.is_valid_int():
			said_turns.append(turn.to_int())
		elif clause.begins_with(HEIGHT) and height.is_valid_int():
			said_heights.append(height.to_int())
		elif clause == WALKABLE or clause == NOT_WALKABLE:
			said_overrides.append(clause == WALKABLE)
		else:
			return false
	if TileKinds.number_of(clauses[0]) < 0:
		return false
	kind = TileKinds.number_of(clauses[0])
	turns = said_turns
	walkable_overrides = said_overrides
	heights = said_heights
	return true
