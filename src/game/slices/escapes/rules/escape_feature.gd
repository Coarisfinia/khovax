class_name EscapeFeature
extends Feature
## Escaping at a health line (#2411, from #1995): a wild monster its region's legend marks
## `, escaping at <percent>%` (WildSpot) is never felled and never dominated. Once its HP is down
## to that share of its full HP, or a ring sealing around it has only that share of its seal ticks
## left, it escapes: the ring around it, sealing or waiting for a totem, breaks without a
## domination (DominationFeature.break_ring), and it leaves the instance through a portal (a
## WildMonsterEscaped event), emitting the event its legend names for it as fainting does (#541).
## So the fight still counts, and no domination is handed out only to be taken back.
##
## A hit that would take it past its line stops at it (HealthFeature.hold_at), and a seal can't
## hold before its line: at least one of its ticks is left there, and this steps right after
## domination, so a seal that reached the line breaks in the same tick. Switched off, it holds
## nobody, and its escapers faint and are dominated like any other wild monster.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "escapes"

## Each standing escaper's line, the share of the way left where it escapes, in thousandths
## (Fixed), by its entity id.
var lines: Dictionary[int, int] = {}
## The event each escaper that emits one emits as it escapes (#541), its legend's name for it, by
## its entity id.
var emits: Dictionary[int, String] = {}


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [HealthFeature.ID, WildMonsterFeature.ID]
	return needed


## The seals it breaks, which an instance may lack: then only a monster's HP can reach its line.
func after() -> Array[String]:
	var earlier: Array[String] = [DominationFeature.ID]
	return earlier


## Every wild monster standing on a spot its legend marks escaping escapes at its spot's line.
func start(state: GameState) -> void:
	var placed: Dictionary[Vector2i, String] = state.region.placed(WildSpotPlacements.KIND)
	for monster: int in _wild(state).monsters:
		var tile: Vector2i = state.entity(monster).tile
		var spot: WildSpot = WildSpot.read(placed[tile]) if placed.has(tile) else null
		if spot != null and spot.escapes_at > 0:
			lines[monster] = spot.escapes_at
			if not spot.emits.is_empty():
				emits[monster] = spot.emits
	_hold(state)


## Holds every escaper at its line, then lets go of the ones that fainted while it was off and lets
## every one that reached its line escape, in id order. Who reached it is settled before anyone
## escapes, so escapers sharing a seal that reached their lines together all escape, though the
## first breaks it.
func step(state: GameState, _commands: Array[Command]) -> void:
	_hold(state)
	var wild: WildMonsterFeature = _wild(state)
	var due: Array[int] = []
	for monster: int in _escapers():
		if not wild.monsters.has(monster):
			_let_go(state, monster)
		elif _at_line(state, monster):
			due.append(monster)
	for monster: int in due:
		_escape(state, monster)


## Off, it holds nobody at a line, so its escapers can faint (HealthFeature.hold_at).
func disabled(state: GameState) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for monster: int in lines:
		health.hold_at(monster, 0)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = lines.erase(removed_id)
	_dropped = emits.erase(removed_id)


## Whether any wild monster spot of `region` is marked escaping, so its instance needs the
## feature.
static func has_escaper(region: Region) -> bool:
	var placed: Dictionary[Vector2i, String] = region.placed(WildSpotPlacements.KIND)
	for tile: Vector2i in placed:
		var spot: WildSpot = WildSpot.read(placed[tile])
		if spot != null and spot.escapes_at > 0:
			return true
	return false


## Keeps every escaper at its line's HP or more against every hit: pushed again each tick, like
## a shield (HealthFeature.shield), so it follows its full HP and is never left behind.
func _hold(state: GameState) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for monster: int in _escapers():
		health.hold_at(monster, _least_hp(state, monster))


## The HP the escaper `monster` escapes at: its line's share of its full HP, at least 1.
func _least_hp(state: GameState, monster: int) -> int:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	return maxi(Fixed.scale(health.max_hp_of(state, monster), lines[monster]), 1)


## Whether the escaper `monster` reached its line: its HP is down to it, or a ring sealing around
## it has only its line's share of its seal ticks left, at least one.
func _at_line(state: GameState, monster: int) -> bool:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if health.hp_of(state, monster) <= _least_hp(state, monster):
		return true
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var dominator_id: int = _sealing_around(domination, monster)
	if dominator_id == 0:
		return false
	var seal: RingSeal = domination.seals[dominator_id]
	var line: int = maxi(Fixed.scale(seal.seal_ticks, lines[monster]), 1)
	return seal.seal_ticks - seal.ticks <= line


## The dominator whose ring seals around the wild monster `monster` in `domination`, or 0.
static func _sealing_around(domination: DominationFeature, monster: int) -> int:
	if domination == null:
		return 0
	for dominator_id: int in domination.seals:
		if domination.seals[dominator_id].monsters.has(monster):
			return dominator_id
	return 0


## The escaper `monster` breaks the ring around it, if any, and leaves the instance through a
## portal, emitting its legend's event.
func _escape(state: GameState, monster: int) -> void:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var dominator_id: int = _sealing_around(domination, monster)
	if dominator_id == 0 and domination != null:
		dominator_id = domination.waiting_dominator(monster)
	if dominator_id != 0:
		var wall: Vector2i = domination.wall_pushed_by(state, monster, dominator_id)
		domination.break_ring(state, dominator_id, wall)
	var wild: WildMonsterFeature = _wild(state)
	var escaped: WildMonsterEscaped = WildMonsterEscaped.new(
		monster,
		state.entity(monster).tile,
		wild.species_of(monster),
		wild.short_id_of(monster),
	)
	escaped.target = wild.target_of(monster)
	var emitted: String = emits.get(monster, "")
	state.remove_entity(monster)
	state.events.append(escaped)
	if not emitted.is_empty():
		state.events.append(EventEmitted.new(emitted))


## Stops holding `monster`, which fainted while the feature was off, at a line: it's no escaper.
func _let_go(state: GameState, monster: int) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	health.hold_at(monster, 0)
	var _dropped: bool = lines.erase(monster)
	_dropped = emits.erase(monster)


## The escapers' entity ids, in id order.
func _escapers() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(lines.keys())
	ids.sort()
	return ids


static func _wild(state: GameState) -> WildMonsterFeature:
	return state.feature(WildMonsterFeature.ID) as WildMonsterFeature


func hash_values() -> Array[int]:
	var values: Array[int] = [lines.size()]
	values.append_array(DataReader.flat_pairs(lines))
	values.append(emits.size())
	for monster: int in _escapers():
		if emits.has(monster):
			values.append_array([monster, StateHash.name_code(emits[monster])])
	return values


## Every escaper's line, and the event it emits, if any, by its entity id.
func save_values() -> Dictionary:
	var emitting: Array[Dictionary] = []
	for monster: int in _escapers():
		if emits.has(monster):
			emitting.append({ "escaper": monster, "emits": emits[monster] })
	return { "lines": DataReader.flat_pairs(lines), "emits": emitting }


## Restores the escapers' lines, each a wild monster's, from 1 to 999 thousandths, and holds them at
## them while the feature is on (off, it holds nobody). One that fainted while the feature was off
## is still among them, as in the run that saved it, until its next step lets it go.
func load_values(state: GameState, values: DataReader) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for monster: int in lines:
		health.hold_at(monster, 0)
	lines.clear()
	var saved: Dictionary[int, int] = values.pairs("lines", 0, DataReader.MOST)
	for monster: int in saved:
		var line: int = saved[monster]
		var wild: WildMonsterFeature = _wild(state)
		var known: bool = wild.monsters.has(monster) or wild.is_fainted(monster)
		if not known or line <= 0 or line >= Fixed.ONE:
			values.fail("escaper %d isn't one wild monster with a line" % monster)
			return
		lines[monster] = line
	_load_emits(values)
	if enabled:
		_hold(state)


## Restores the events the escapers emit, each an id, for an escaper the lines named.
func _load_emits(values: DataReader) -> void:
	emits.clear()
	for entry: DataReader in values.entries("emits"):
		var monster: int = entry.whole("escaper", 1, DataReader.MOST)
		var emitted: String = entry.text("emits")
		if not lines.has(monster) or emits.has(monster) or not Ids.is_id(emitted):
			values.fail("escaper %d doesn't emit one event" % monster)
			return
		emits[monster] = emitted
