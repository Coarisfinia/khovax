extends RefCounted
## Domination flow (#20, #219): the player walks a ring around the basic region's wild monster at
## (-2, 0), and the ring waits for a totem (#423), the monster encircled, until it wears the ring
## through (#422); a totem placed off the ring, or by a player out of charges, does nothing. The
## player's totem placed on the ring (the place_totem key) spends a charge, and the ring seals: the
## monster pushes on it, and once the ring has held for its seal ticks (not a tick before) the
## monster is dominated: it leaves the world, the domination is announced, the trail starts over,
## and its figure shrinks away. While it seals, the ring fills on screen and a save resumes it
## exactly. An open ring, a walk that only touches the wild monster, and a ring around another tile
## dominate nothing. Allies share one trail (#87): two players close one ring together, and the
## domination goes to the lowest slot among those who colored its wall (owner, #86), whoever's move
## closed it; the ring then comes off the trail, the trail leading up to it stays. A ring around
## several monsters splits them by contribution (#260): two allies who each colored half of it get
## one each, and the owner's examples split as decided. Domination is deterministic. A domination by
## this machine's player lands in their profile and its save at once (#132), as the species it was:
## named by its spot, or rolled from the blueprint's list (#133).
##
## The issue's outcomes (#219), at level 1 with the placeholder constants, in a disc of test
## monsters: a weak one holds in a small ring and in a big one; many weak ones break a big ring; a
## strong one breaks a big ring fast, and a small ring too, only later (the issue leaves that to
## level and weakening). A broken ring dominates nothing, says so, and starts its trail over. A
## second player standing on the wall segment the strong one pushes on reinforces it (#227), and
## the small ring holds; standing on any other segment of it, they don't, and it breaks.
##
## A wild monster where no ring could enclose it (#364), on the region's edge or beside rock that
## runs to the edge, steps away at its own pace to the nearest tile where one could and stays
## there, where a ring dominates it; one a ring could enclose already never moves, and neither does
## one held where it stands (as hiding ones are).
##
## A companion (#221) strikes the wild monster next to it once a second for its species'
## strength, never below 1 HP, one encircled by a ring waiting for a totem too (#423), and leaves
## one hiding in its tile alone, and one sealing in a ring (#409): its seal was worked out from its
## HP, so a save taken mid-seal resumes. A save taken while a ring waits resumes too. Its player
## fires its special attack (#410): lethal, it fells the wild monster next to it, which faints for
## good where it fell, and then it cools down. A wild monster strikes once a second too (#422): the
## companion next to it first, then the player, then the trail, whose tile gives way once worn
## through; encircled, it strikes only its ring's wall, and wearing through it breaks the ring.
##
## A wild monster in a tile that hides (#202), the glade pond's in its shrubs, starts hidden and
## jumps out once the player comes next to it, not a step before. A legend can only hide one in a
## tile that hides.

## Where the flow's profile is saved, apart from the player's own.
const SAVE_PATH: String = "user://test_domination_profile.json"
## The two halves of the ring around the wild monster that two allies walk (#87): the first player
## from its start at (1, -1), the second from its start at (-1, 1). The second's last step closes
## it.
const FIRST_HALF: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-2, -1),
	Vector2i(-3, 0),
]
const SECOND_HALF: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(-2, 1),
	Vector2i(-3, 1),
]
## A ring around (1, 1), with no wild monster inside.
const OTHER_RING: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(2, 0),
	Vector2i(2, 1),
	Vector2i(1, 2),
	Vector2i(0, 2),
	Vector2i(0, 1),
]
const WILD_MONSTER_TILE: Vector2i = Vector2i(-2, 0)
## Ticks a seal may take at most in this flow, before it counts as stuck.
const MOST_SEAL_TICKS: int = 400
## The companion the first player brings into the saved world.
const COMPANION: String = "moss_toad"
## The outcome tests' species, in a disc region of radius OUTCOME_RADIUS: a weak and a strong one,
## both at full HP.
const OUTCOME_RADIUS: int = 4
const WEAK: String = "weak"
const STRONG: String = "strong"
const OUTCOME_HP: int = 100
const WEAK_STRENGTH: int = 40
const STRONG_STRENGTH: int = 400
## The weak species' special: three times its strength, more than a weak monster's HP, and its
## cooldown.
const SPECIAL_POWER: int = 3000
const SPECIAL_TICKS: int = 50
## A small ring and a big one around the disc's middle, by their radius.
const SMALL_RING: int = 1
const BIG_RING: int = 3
## The HP the enrage check wears its monster down to before enraging it further.
const WORN: int = 10
## No second player on the outcome's wall.
const NO_HELPER: int = -1
## Where many weak monsters stand in the big ring.
const CROWD: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


func run(tree: SceneTree) -> String:
	var result: String = _check_open_ring()
	if result.is_empty():
		result = _check_other_ring()
	if result.is_empty():
		result = _check_domination()
	if result.is_empty():
		result = _check_seal_saved()
	if result.is_empty():
		result = _check_together()
	if result.is_empty():
		result = _check_outcomes()
	if result.is_empty():
		result = _check_species()
	if result.is_empty():
		result = await _check_view(tree)
	if result.is_empty():
		result = await _check_saved(tree)
	return result


## The glade's wild monster in the shrubs starts hidden, and jumps out on the step that brings the
## player next to it, once; a legend can't hide one in plain ground.
func _check_hiding() -> String:
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 0)
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	if hiding == null or hiding.hidden.size() != 1:
		return "the glade's wild monster in the shrubs doesn't start hidden"
	var monster: int = hiding.hidden[0]
	var tile: Vector2i = state.entity(monster).tile
	var path: Array[int] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		if path.is_empty() and FlowSteps.walkable_for_players(state, tile + direction):
			path = FlowSteps.shortest_path(state, state.player(0).tile, tile + direction)
	if path.is_empty():
		return "no way leads next to the hidden wild monster on %s" % tile
	var jumps: int = 0
	for direction: int in path:
		var events: Array[RefCounted] = FlowSteps.step(state, direction)
		var near: bool = Hex.distance(state.player(0).tile, tile) <= HidingFeature.NEAR
		for event: RefCounted in events:
			jumps += 1 if event is MonsterJumpedOut else 0
		if near != (jumps == 1) or hiding.is_hidden(monster) == near:
			return "on %s, next to it: %s, it jumped out %d times" % [
				state.player(0).tile,
				near,
				jumps,
			]
		if near:
			break
	if jumps != 1:
		return "the hidden wild monster jumped out %d times" % jumps
	return _check_hiding_legend()


## A legend hides a wild monster in shrubs, which hide, but not in ground, which doesn't.
func _check_hiding_legend() -> String:
	var piece: String = "# Hiding

## Tiles

```
h
```

## Legend

- `h`: "
	piece += RegionDocument.HIDING
	var shrubs: Region = RegionDocument.parse(piece + "shrubs
")
	if not shrubs.problem.is_empty() or shrubs.wild_monsters != [Vector2i.ZERO]:
		return "a wild monster hiding in shrubs doesn't read: " + shrubs.problem
	if not HidingFeature.hides_at(shrubs, Vector2i.ZERO):
		return "the wild monster said to hide in shrubs isn't on shrubs"
	if RegionDocument.parse(piece + "ground
").problem.is_empty():
		return "a legend hid a wild monster in plain ground"
	return _check_companion_strikes()


## Every ring tile but the last: the walk passes right by the wild monster and dominates nothing.
func _check_open_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var ring: Array[Vector2i] = FlowSteps.BASIC_RING
	var _events: Array[RefCounted] = FlowSteps.walk(state, ring.slice(0, ring.size() - 1))
	if _wild(state).monsters.size() != 1 or not _domination(state).seals.is_empty():
		return "an open ring dominated the wild monster or started sealing"
	if not _domination(state).encircled.is_empty():
		return "an open ring encircled the wild monster"
	return ""


## A closed ring around another tile leaves the wild monster alone, and the trail keeps growing.
func _check_other_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = FlowSteps.walk(state, OTHER_RING)
	var trail: Trail = _trails(state).shared
	if _wild(state).monsters.size() != 1 or trail.tiles.size() != OTHER_RING.size() + 1:
		return "a ring around another tile dominated the wild monster or reset the trail"
	if not _domination(state).seals.is_empty() or not _domination(state).encircled.is_empty():
		return "a ring around no wild monster started sealing or waited for a totem"
	return _check_waits_for_totem()


## The full ring doesn't seal by itself (#423): it waits for a totem, the wild monster encircled. A
## totem placed one step off the ring does nothing; back on it, the totem spends one
## charge and the ring seals, and holding it there spends no more. A player out of charges places
## none.
func _check_waits_for_totem() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var monster_id: int = _wild(state).monsters[0]
	var player: Entity = state.player(0)
	var domination: DominationFeature = _domination(state)
	var _walked: Array[RefCounted] = FlowSteps.walk(state, FlowSteps.BASIC_RING)
	# A while, but not so long that the monster wears the ring through (#422).
	for _tick: int in 2 * WildAttackFeature.STRIKE_TICKS:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if not domination.seals.is_empty() or not domination.is_encircled(monster_id):
		return "a closed ring didn't wait for a totem with the wild monster encircled"
	var walls: Array[Vector2i] = domination.ring_waiting(state, player.id)
	if domination.encircled.keys() != [player.id] or walls.size() != Hex.ring(1).size():
		return "the ring waiting for a totem isn't the player's six tiles: %s" % [walls]
	var ring_tile: Vector2i = player.tile
	_walked = FlowSteps.step(state, Hex.DIRECTIONS.find(Vector2i(1, 0)))
	Simulation.step(state, FlowSteps.totem())
	var left: int = domination.totems.charges_of(player.id)
	if not domination.seals.is_empty() or left != PlaceholderTotems.CHARGES:
		return "a totem placed off the ring started sealing or spent a charge"
	_walked = FlowSteps.step(state, Hex.DIRECTIONS.find(ring_tile - player.tile))
	for _tick: int in 2:
		Simulation.step(state, FlowSteps.totem())
	var spent: int = PlaceholderTotems.CHARGES - domination.totems.charges_of(player.id)
	if domination.seals.keys() != [player.id] or not domination.encircled.is_empty() or spent != 1:
		return "a totem held on the ring started no seal, or spent %d charges, not 1" % spent
	return _check_out_of_charges()


## A player whose totem has no charge left places none: the ring goes on waiting.
func _check_out_of_charges() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var player: Entity = state.player(0)
	var _walked: Array[RefCounted] = FlowSteps.walk(state, FlowSteps.BASIC_RING)
	while _domination(state).totems.spend(player.id):
		pass
	Simulation.step(state, FlowSteps.totem())
	if not _domination(state).seals.is_empty() or _domination(state).encircled.is_empty():
		return "a totem without charges started a seal"
	return ""


## The full ring seals around the wild monster: it stays until the ring has held for its seal
## ticks, which grow with the monster's pressure, and is dominated exactly then: gone, the
## domination announced with who dominated it, the trail started over from the dominator's tile, and
## the same walk always ending in the same state.
func _check_domination() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var monster_id: int = _wild(state).monsters[0]
	_close(state, FlowSteps.BASIC_RING)
	var closed: int = state.tick
	var player: Entity = state.player(0)
	var seal: RingSeal = _domination(state).seals.get(player.id)
	if seal == null or state.entity(monster_id) == null or seal.monsters != [monster_id]:
		return "the totem on the closed ring didn't start sealing the wild monster in"
	var expected_ticks: int = RingSealing.SEAL_BASE_TICKS + Fixed.div_floor(
		RingSealing.pressure(_wild(state), monster_id),
		RingSealing.SEAL_PRESSURE_PER_TICK,
	)
	if seal.seal_ticks != expected_ticks or seal.walls.size() != Hex.ring(1).size():
		return "the seal takes %d ticks with %d walls, not %d with six" % [
			seal.seal_ticks,
			seal.walls.size(),
			expected_ticks,
		]
	var events: Array[RefCounted] = _settle(state)
	var dominated: Array[WildMonsterDominated] = _dominated(events)
	if dominated.size() != 1 or state.tick - closed != expected_ticks:
		return "the seal ended %d ticks after closing, not %d, with %d dominations" % [
			state.tick - closed,
			expected_ticks,
			dominated.size(),
		]
	var expected: bool = (
		dominated[0].monster_id == monster_id and dominated[0].dominator_id == player.id
	)
	if not expected or dominated[0].tile != WILD_MONSTER_TILE or state.entity(monster_id) != null:
		return "the domination wasn't announced once, by the player, on the wild monster's tile"
	# A ring walked alone: all six wall tiles are the dominator's, the full loot (#86).
	var looted: String = _check_loot(events, dominated[0], [DominationLootFeature.FULL_ROLLS, 0])
	if not looted.is_empty():
		return looted
	return _check_after_domination(state)


## The domination's loot (#86): each slot earned `rolls` (by slot) for what it did for the ring, and
## the domination's DominationLoot gives exactly the slots that earned any, when its species has a
## loot table; a species without one drops nothing. A player who only braced the wall for a second
## earns nothing.
func _check_loot(
	events: Array[RefCounted],
	dominated: WildMonsterDominated,
	rolls: Array[int],
) -> String:
	for slot: int in rolls.size():
		if DominationLootFeature.rolls_for(dominated, slot) != rolls[slot]:
			return "slot %d earned %d rolls for the domination, not %d" % [
				slot,
				DominationLootFeature.rolls_for(dominated, slot),
				rolls[slot],
			]
	var earning: Array[int] = []
	for slot: int in rolls.size():
		if rolls[slot] > 0:
			earning.append(slot)
	var looted: Array = []
	for event: RefCounted in events:
		if event is DominationLoot and (event as DominationLoot).monster_id == dominated.monster_id:
			looted = (event as DominationLoot).loot.keys()
	looted.sort()
	var tabled: bool = LootContent.load_loot_tables().loot_tables.has(dominated.species)
	if looted != (earning if tabled else []):
		return "the %s's loot went to slots %s, not %s" % [dominated.species, looted, earning]
	var brief: WildMonsterDominated = WildMonsterDominated.new(
		1,
		1,
		0,
		Vector2i.ZERO,
		dominated.species,
	)
	brief.braced_ticks[0] = Simulation.TICKS_PER_SECOND
	if DominationLootFeature.rolls_for(brief, 0) != 0:
		return "a second on the wall earned loot"
	return ""


## After the domination, the ring is off the trail but for the tile the dominator stands on (#87),
## the trail leading up to it stays, and the same walk always ends in the same state.
func _check_after_domination(state: GameState) -> String:
	var player: Entity = state.player(0)
	var trail: Trail = _trails(state).shared
	var expected: Array[Vector2i] = [Vector2i(1, -1), FlowSteps.BASIC_RING[0], player.tile]
	expected.sort()
	if trail.sorted_tiles() != expected:
		return "the ring didn't come off the trail after dominating: %s" % [trail.sorted_tiles()]
	var again: GameState = InstanceBlueprints.basic(42)
	_close(again, FlowSteps.BASIC_RING)
	var _events: Array[RefCounted] = _settle(again)
	if again.state_hash() != state.state_hash():
		return "the same domination gave two different states"
	return ""


## A world saved while a ring waits for a totem resumes as it was, and one saved while it seals
## resumes the seal exactly: the same hash, and both copies dominate the monster on the same tick.
## A second player stands by, for the refused saves. The first player's companion stands next to
## the monster: it strikes it while the ring waits (#423), and never while it seals (#409).
func _check_seal_saved() -> String:
	var world: World = World.new(
		BlueprintSource.new(),
		42,
		InstanceBlueprints.BASIC,
		2,
		[COMPANION],
	)
	for next: Vector2i in FlowSteps.BASIC_RING:
		var direction: int = Hex.DIRECTIONS.find(next - world.player(0).tile)
		for tick: int in MovementFeature.MOVE_TICKS:
			var first: int = direction if tick == 0 else Command.NO_MOVE
			world.step(FlowSteps.commands([first, Command.NO_MOVE]))
	var waited: String = _check_wait_saved(world)
	if waited.is_empty():
		waited = _check_strikes_in_ring(world, false)
	if not waited.is_empty():
		return waited
	world.step(FlowSteps.totem(0, 2))
	for _tick: int in Fixed.div_floor(RingSealing.SEAL_BASE_TICKS, 4):
		world.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
	var struck: String = _check_strikes_in_ring(world, true)
	if not struck.is_empty():
		return struck
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	if _domination(basic).seals.is_empty():
		return "the world's ring wasn't sealing when saved"
	var refused: String = _check_seal_refused(world)
	if not refused.is_empty():
		return refused
	var resumed: World = WorldSave.parse(WorldSave.to_text(world))
	if not resumed.problem.is_empty() or resumed.state_hash() != world.state_hash():
		return "the world saved mid-seal didn't resume as it was: " + resumed.problem
	for _tick: int in MOST_SEAL_TICKS:
		world.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		resumed.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		if resumed.state_hash() != world.state_hash():
			return "the resumed seal went another way at tick %d" % world.tick
	if not _wild(resumed.instances[InstanceBlueprints.BASIC]).monsters.is_empty():
		return "the resumed seal didn't dominate the wild monster"
	return ""


## A world saved while its basic instance's ring waits for a totem resumes as it was, and a save
## whose waiting ring names its monster twice is refused.
func _check_wait_saved(world: World) -> String:
	var resumed: World = WorldSave.parse(WorldSave.to_text(world))
	if not resumed.problem.is_empty() or resumed.state_hash() != world.state_hash():
		return "the world saved while its ring waited didn't resume as it was: " + resumed.problem
	var data: Dictionary = WorldData.of(world)
	var waiting: Array = _domination_values(data)["waiting"]
	if waiting.size() != 1:
		return "the world's save holds %d rings waiting for a totem, not 1" % waiting.size()
	var monster_id: int = waiting[0]["monsters"][0]
	waiting[0]["monsters"] = [monster_id, monster_id]
	var problem: String = WorldData.to_world(data, BlueprintSource.new()).problem
	if not problem.contains("there twice"):
		return "a waiting ring with its monster twice wasn't refused for it: " + problem
	return ""


## Keeps the first player's companion next to the wild monster in the world's basic instance's
## ring for a little longer than it waits between strikes: it strikes it while the ring waits for
## a totem (#423), and never while it seals (#409).
func _check_strikes_in_ring(world: World, sealing: bool) -> String:
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var companions: CompanionFeature = basic.feature(Features.COMPANIONS) as CompanionFeature
	var companion: Entity = basic.entity(companions.companion_of(0))
	if companion == null:
		return "the first player's companion didn't join them"
	var struck: bool = false
	for _tick: int in CompanionAttackFeature.STRIKE_TICKS + 1:
		var ringed: bool = not _domination(basic).encircled.is_empty()
		if sealing:
			ringed = not _domination(basic).seals.is_empty()
		if not ringed:
			return "the ring stopped sealing or waiting before the companion stood by it"
		companion.tile = WILD_MONSTER_TILE + Hex.DIRECTIONS[2]
		world.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		for event: RefCounted in basic.events:
			struck = struck or event is CompanionStruck
	if struck == sealing:
		return "the companion struck: %s, the ring sealing: %s" % [struck, sealing]
	return ""


## A save whose seal names its monster twice, or puts it in a second player's seal too, is refused
## whole: neither could have happened, and a monster sealed twice would be dominated twice.
func _check_seal_refused(world: World) -> String:
	var data: Dictionary = WorldData.of(world)
	var twice: Dictionary = data.duplicate(true)
	var seal: Dictionary = _seals_in(twice)[0]
	var monster_id: int = seal["monsters"][0]
	seal["monsters"] = [monster_id, monster_id]
	var two_seals: Dictionary = data.duplicate(true)
	var first: Dictionary = _seals_in(two_seals)[0]
	var other: Dictionary = first.duplicate(true)
	other["catcher"] = world.player(1).id
	_seals_in(two_seals).append(other)
	var cases: Dictionary[String, Dictionary] = {
		"there twice": twice,
		"in another seal": two_seals,
	}
	var source: BlueprintSource = BlueprintSource.new()
	for expected: String in cases:
		var problem: String = WorldData.to_world(cases[expected], source).problem
		if not problem.contains(expected):
			return "a seal %s wasn't refused for it: %s" % [expected, problem]
	return ""


## The saved seals of the basic instance in the world's save `data`, as saved: changing them
## changes `data`.
func _seals_in(data: Dictionary) -> Array:
	return _domination_values(data)["seals"]


## The basic instance's saved domination in the world's save `data`, as saved.
func _domination_values(data: Dictionary) -> Dictionary:
	for instance: Dictionary in data["instances"]:
		if instance["name"] != InstanceBlueprints.BASIC:
			continue
		for feature: Dictionary in instance["state"]["features"]:
			if feature["id"] == Features.DOMINATION:
				return feature["values"]
	return { "seals": [], "waiting": [] }


## Two allies close one ring together (#87): the first player walks half of it, then the second
## the rest, and the second's step closes it. The second places their totem on it, and the
## domination still goes to the first, the lowest slot among those who colored its wall (owner,
## #86). Then the ring is off the trail, but the trail
## leading up to it stays, and each player colors the tile they stand on.
func _check_together() -> String:
	var state: GameState = InstanceBlueprints.basic(42, 2)
	var first: Entity = state.player(0)
	var second: Entity = state.player(1)
	var starts: Array[Vector2i] = [first.tile, second.tile]
	var events: Array[RefCounted] = _walk_slot(state, 0, FIRST_HALF)
	if not _domination(state).seals.is_empty():
		return "half a ring started sealing"
	events.append_array(_walk_slot(state, 1, SECOND_HALF))
	if _domination(state).encircled.keys() != [first.id]:
		return "the allies' ring waits for %s, not the first player" % [
			_domination(state).encircled.keys(),
		]
	Simulation.step(state, FlowSteps.totem(1, 2))
	events.append_array(state.events)
	var spent: bool = (
		_domination(state).totems.charges_of(second.id)
		< _domination(state).totems.charges_of(first.id)
	)
	if _domination(state).seals.keys() != [first.id] or not spent:
		return "the second's totem started the seal for %s, not the first player" % [
			_domination(state).seals.keys(),
		]
	for _tick: int in MOST_SEAL_TICKS:
		Simulation.step(state, FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		events.append_array(state.events)
	var dominated: Array[WildMonsterDominated] = _dominated(events)
	if dominated.size() != 1 or dominated[0].dominator_id != first.id:
		return "the allies' ring dominated %d times, not once for the first" % dominated.size()
	# Each colored half the wall: three tiles each, two rolls each (#86).
	var problem: String = _check_loot(events, dominated[0], [2, 2])
	var expected: Array[Vector2i] = [starts[0], starts[1], FIRST_HALF[0], first.tile, second.tile]
	expected.sort()
	var trail: Trail = _trails(state).shared
	if trail.sorted_tiles() != expected:
		return "after the allies' domination the trail is %s, not %s" % [
			trail.sorted_tiles(),
			expected,
		]
	if trail.tiles[first.tile] != first.id or trail.tiles[second.tile] != second.id:
		return "the players' fresh trail tiles aren't their own"
	return problem if not problem.is_empty() else _check_shared_domination()


## Two weak wild monsters in one ring that two allies closed together, each coloring half of its
## wall: each gets one (#260). And the owner's examples: shares round to the closest whole monster,
## what rounding leaves over goes to the largest share still owed, ties to whoever joined first.
func _check_shared_domination() -> String:
	var splits: Dictionary[String, Array] = {
		"40/60": [[4, 6], [1, 2]],
		"40/40/20": [[4, 4, 2], [1, 2]],
		"thirds": [[1, 1, 1], [1, 2]],
		"90/10": [[9, 1], [1, 1]],
	}
	for example: String in splits:
		var amounts: Array = splits[example][0]
		if _split(amounts, 2) != splits[example][1]:
			return "two monsters at %s went to %s, not %s" % [
				example,
				_split(amounts, 2),
				splits[example][1],
			]
	var state: GameState = _outcome_state(WEAK, [Vector2i.ZERO, Hex.DIRECTIONS[0]])
	var ring: Array[Vector2i] = Hex.ring(2)
	var first: Entity = state.add_entity(0, ring[0])
	var second: Entity = state.add_entity(1, ring[6])
	var events: Array[RefCounted] = _walk_slot(state, 0, ring.slice(1, 6))
	events.append_array(_walk_slot(state, 1, ring.slice(7)))
	events.append_array(_settle(state))
	var takers: Array[int] = []
	for dominated: WildMonsterDominated in _dominated(events):
		takers.append(dominated.dominator_id)
	takers.sort()
	if takers != [first.id, second.id]:
		return "two allies who each colored half a ring around two monsters got %s" % [takers]
	return ""


## Who gets each of `count` monsters from players with these contributions (entity ids 1 and up),
## sorted.
static func _split(amounts: Array, count: int) -> Array[int]:
	var done: Dictionary[int, int] = {}
	for i: int in amounts.size():
		done[i + 1] = amounts[i]
	var monsters: Array[int] = []
	for i: int in count:
		monsters.append(100 + i)
	var takers: Array[int] = []
	takers.assign(DominationShares.hand_out(monsters, done).values())
	takers.sort()
	return takers


## Walks the player in `slot` along `path` while the other player stands; returns the events.
func _walk_slot(state: GameState, slot: int, path: Array[Vector2i]) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	var standing: Array[int] = [Command.NO_MOVE, Command.NO_MOVE]
	for next: Vector2i in path:
		var moves: Array[int] = standing.duplicate()
		moves[slot] = _toward(state.player(slot), next)
		for tick: int in MovementFeature.MOVE_TICKS:
			# Each step's move is given on its first tick only.
			Simulation.step(state, FlowSteps.commands(moves if tick == 0 else standing))
			events.append_array(state.events)
	return events


## The issue's outcomes table, each in its own disc of test monsters.
func _check_outcomes() -> String:
	var origin: Array[Vector2i] = [Vector2i.ZERO]
	var weak_small: Vector2i = _outcome(WEAK, SMALL_RING, origin)
	var weak_big: Vector2i = _outcome(WEAK, BIG_RING, origin)
	var crowd_big: Vector2i = _outcome(WEAK, BIG_RING, CROWD)
	var strong_big: Vector2i = _outcome(STRONG, BIG_RING, origin)
	var strong_small: Vector2i = _outcome(STRONG, SMALL_RING, origin)
	var reinforced: Vector2i = _outcome(STRONG, SMALL_RING, origin, 0)
	var beside: Vector2i = _outcome(STRONG, SMALL_RING, origin, 1)
	if weak_small.x != 1 or weak_big.x != 1:
		return "a weak monster broke out of a small (%s) or a big ring (%s)" % [
			weak_small,
			weak_big,
		]
	if crowd_big.x != 0 or strong_big.x != 0 or strong_small.x != 0:
		return "many weak (%s) or a strong monster (%s, %s) didn't break their ring" % [
			crowd_big,
			strong_big,
			strong_small,
		]
	if strong_big.y >= strong_small.y or strong_big.y >= crowd_big.y:
		return "a strong monster didn't break a big ring fastest: %d ticks, not below %d and %d" % [
			strong_big.y,
			strong_small.y,
			crowd_big.y,
		]
	if reinforced.x != 1 or beside.x != 0:
		return "a ring reinforced where a strong monster pushes (%s) or beside (%s) went wrong" % [
			reinforced,
			beside,
		]
	var enraged: String = _check_enraged()
	return enraged if not enraged.is_empty() else _check_moves_away()


## In a disc with rock running from its edge to (-2, 0): the monster on the edge at (4, 0) and the
## one beside the rock at (-1, 0) can't be ringed, so each steps once within STEP_TICKS, to the
## nearest tile that can, and then stands; the one at (1, 2) never moves, nor the one held on the
## edge at (0, 4). A small ring then dominates the one that came off the rock.
func _check_moves_away() -> String:
	var spots: Array[Vector2i] = [Vector2i(4, 0), Vector2i(-1, 0), Vector2i(1, 2), Vector2i(0, 4)]
	var state: GameState = _outcome_state(WEAK, spots)
	_wild(state).hold(_wild(state).monsters[3], true)
	for rock: Vector2i in [Vector2i(-2, 0), Vector2i(-3, 0), Vector2i(-4, 0)]:
		state.region.terrain[rock] = Region.BLOCKED
	var stuck: Dictionary[Vector2i, bool] = RingableGround.unringable(state.region)
	if (not stuck.has(spots[0])
			or not stuck.has(spots[1])
			or stuck.has(spots[2])
			or not stuck.has(spots[3])):
		return "the tiles no ring encloses are %s" % [stuck.keys()]
	var expected: Array[Vector2i] = [Vector2i(3, 0), Vector2i.ZERO, Vector2i(1, 2), Vector2i(0, 4)]
	for steps: int in [WildMonsterFeature.STEP_TICKS, 3 * WildMonsterFeature.STEP_TICKS]:
		for _tick: int in steps:
			Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		var tiles: Array[Vector2i] = []
		for monster: int in _wild(state).monsters:
			tiles.append(state.entity(monster).tile)
		if tiles != expected:
			return "wild monsters that can't be ringed stand on %s, not %s" % [tiles, expected]
	var off_the_rock: int = _wild(state).monsters[1]
	var ring: Array[Vector2i] = Hex.ring(SMALL_RING)
	var _player: Entity = state.add_entity(0, ring[0])
	_close(state, ring.slice(1))
	var dominated: Array[WildMonsterDominated] = _dominated(_settle(state))
	if dominated.size() != 1 or dominated[0].monster_id != off_the_rock:
		return "a ring around where the monster stepped off the rock didn't dominate it"
	return ""


## Enrage (#220): a strong monster that breaks a small ring comes out of it with a stack of rage,
## stronger than its species; every further broken ring adds a stack (enraged_further).
func _check_enraged() -> String:
	var origin: Array[Vector2i] = [Vector2i.ZERO]
	var state: GameState = _outcome_state(STRONG, origin)
	var ring: Array[Vector2i] = Hex.ring(SMALL_RING)
	var _player: Entity = state.add_entity(0, ring[0])
	_close(state, ring.slice(1))
	# Off the wall, so the dominator doesn't reinforce the ring and it breaks.
	var _events: Array[RefCounted] = _step_off(state)
	_events = _settle(state)
	var wild: WildMonsterFeature = _wild(state)
	if wild.monsters.size() != 1:
		return "the strong monster didn't break out of the small ring"
	var monster: int = wild.monsters[0]
	if wild.rage_of(monster) != 1 or wild.strength_of(monster) <= STRONG_STRENGTH:
		return "a broken ring didn't enrage the monster inside: rage %d, strength %d" % [
			wild.rage_of(monster),
			wild.strength_of(monster),
		]
	return _enraged_further(state, monster)


## A RingBroken event for a ring that had only `monster` inside.
func _broken_around(monster: int) -> RingBroken:
	var inside: Array[int] = [monster]
	var walls: Array[Vector2i] = []
	return RingBroken.new(0, 0, Vector2i.ZERO, walls, inside)


## Saves the wild monsters with `monster` at WORN HP and loads them back: its rage must survive.
func _wear_down(state: GameState, monster: int) -> String:
	var wild: WildMonsterFeature = _wild(state)
	var saved: Dictionary = wild.save_values()
	var entries: Array = saved["wild_monsters"]
	var entry: Dictionary = entries[0]
	entry["hp"] = WORN
	var restored: DataReader = DataReader.new(saved)
	wild.load_values(state, restored)
	if restored.failed() or wild.rage_of(monster) != 1 or wild.hp_of(monster) != WORN:
		return "the monster's rage or HP didn't survive a save: %s" % restored.problem
	return ""


## Every further ring the monster breaks adds a stack, up to the most it takes, each making it
## stronger still and healing EnrageFeature.HEAL of its full HP, never past it: it's worn down to
## WORN HP first (through a save, as nothing hurts monsters yet). Its rage is saved too.
func _enraged_further(state: GameState, monster: int) -> String:
	var worn: String = _wear_down(state, monster)
	if not worn.is_empty():
		return worn
	var wild: WildMonsterFeature = _wild(state)
	var enrage: EnrageFeature = state.feature(Features.ENRAGE) as EnrageFeature
	var broken: Array[RefCounted] = [_broken_around(monster)]
	for stack: int in range(2, WildMonsterFeature.MOST_RAGE + 3):
		var before: int = wild.strength_of(monster)
		state.events = broken
		enrage.step(state, [])
		# Past the most rage, it grows no stronger.
		var stronger: bool = wild.strength_of(monster) > before
		stronger = stronger or stack > WildMonsterFeature.MOST_RAGE
		var rage: int = mini(stack, WildMonsterFeature.MOST_RAGE)
		var healed: int = mini(
			WORN + (stack - 1) * Fixed.scale(OUTCOME_HP, EnrageFeature.HEAL),
			OUTCOME_HP,
		)
		if wild.rage_of(monster) != rage or not stronger or wild.hp_of(monster) != healed:
			return "broken ring %d left rage %d, strength %d, HP %d" % [
				stack,
				wild.rage_of(monster),
				wild.strength_of(monster),
				wild.hp_of(monster),
			]
	return ""


## Plays one outcome: monsters of `species` on `spots`, and the player walking a ring of `radius`
## around the disc's middle, then stepping off it outward, so the wall stands on its own. With a
## `helper`, a second player stands on the wall that many segments after the one the first spot
## pushes on (0: on it). Returns 1 when the ring held and dominated them all, 0 when it broke
## dominating none, -1 otherwise; and the ticks from closing to the end.
func _outcome(
		species: String,
		radius: int,
		spots: Array[Vector2i],
		helper: int = NO_HELPER,
) -> Vector2i:
	var state: GameState = _outcome_state(species, spots)
	var ring: Array[Vector2i] = Hex.ring(radius)
	var player: Entity = state.add_entity(0, ring[0])
	if helper != NO_HELPER:
		_reinforce(state, ring, spots[0], helper)
	_close(state, ring.slice(1))
	var closed: int = state.tick
	var events: Array[RefCounted] = _step_off(state)
	events.append_array(_settle(state))
	var broken: Array[RingBroken] = []
	for event: RefCounted in events:
		if event is RingBroken:
			broken.append(event as RingBroken)
	var held: bool = _dominated(events).size() == spots.size() and broken.is_empty()
	var failed: bool = _dominated(events).is_empty() and broken.size() == 1
	failed = failed and _wild(state).monsters.size() == spots.size()
	failed = failed and broken[0].dominator_id == player.id and broken[0].walls.has(broken[0].tile)
	var result: int = 1 if held else (0 if failed else -1)
	# Held or broken, the ring comes off the trail: none of its wall is left but where players
	# stand.
	var standing: Array[Vector2i] = []
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT:
			standing.append(entity.tile)
	for wall: Vector2i in broken[0].walls if not broken.is_empty() else []:
		if _trails(state).shared.tiles.has(wall) and not standing.has(wall):
			result = -1
	return Vector2i(result, state.tick - closed)


## Puts a player in slot 1 on `ring`'s wall, `offset` segments after the one the monster on `spot`
## will push.
func _reinforce(state: GameState, ring: Array[Vector2i], spot: Vector2i, offset: int) -> void:
	# The ring's wall is the whole ring, in sorted order, as nothing else stands inside it.
	var walls: Array[Vector2i] = ring.duplicate()
	walls.sort()
	var segment: int = (RingShape.nearest(walls, spot) + offset) % walls.size()
	var _helper: Entity = state.add_entity(1, walls[segment])


## Steps the player in slot 0 off the ring, away from the disc's middle, once their last step is
## done, unless the seal ends first; returns every event raised meanwhile.
func _step_off(state: GameState) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	var from: Vector2i = state.player(0).tile
	var away: int = Command.NO_MOVE
	for direction: int in Hex.DIRECTIONS.size():
		if Hex.distance(
			from + Hex.DIRECTIONS[direction],
			Vector2i.ZERO,
		) > Hex.distance(from, Vector2i.ZERO):
			away = direction
	while state.player(0).tile == from and not _domination(state).seals.is_empty():
		Simulation.step(state, FlowSteps.command(away))
		events.append_array(state.events)
	return events


## A disc with monsters of `species` on `spots`, and no player yet.
func _outcome_state(species: String, spots: Array[Vector2i]) -> GameState:
	var region: Region = Region.disc(OUTCOME_RADIUS)
	region.wild_monsters = spots
	# One shared spot: the regions only read it.
	var named: WildSpot = WildSpot.new(species)
	for spot: Vector2i in spots:
		region.wild_spots[spot] = named
	var hp: Dictionary[String, int] = { WEAK: OUTCOME_HP, STRONG: OUTCOME_HP }
	var strength: Dictionary[String, int] = { WEAK: WEAK_STRENGTH, STRONG: STRONG_STRENGTH }
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		WildMonsterFeature.new([], [], hp, strength),
		DominationFeature.new(),
		EnrageFeature.new(),
	]
	return GameState.new(region, 1, ordered)


## A weak companion hemmed in by weak wild monsters strikes the one with the lowest id at once
## and then every STRIKE_TICKS, for its strength each time, until it holds at 1 HP; with them all
## hidden in their tiles, it strikes none.
func _check_companion_strikes() -> String:
	var hemmed: Vector2i = Vector2i(2, 0)
	var spots: Array[Vector2i] = []
	for side: Vector2i in Hex.DIRECTIONS:
		spots.append(hemmed + side)
	var state: GameState = _strike_state(spots)
	state.companions[0] = WEAK
	var _player: Entity = state.add_entity(0, Vector2i(-2, 0))
	if not _strikes_over(state, 1).is_empty():
		return "the companion struck before it stood next to a wild monster"
	var companion_id: int = (state.feature(Features.COMPANIONS) as CompanionFeature).companion_of(0)
	state.entity(companion_id).tile = hemmed
	var first: int = _wild(state).monsters[0]
	var ticks: int = 4 * CompanionAttackFeature.STRIKE_TICKS
	var strikes: Array[CompanionStruck] = _strikes_over(state, ticks)
	var damages: Array[int] = []
	for strike: CompanionStruck in strikes:
		damages.append(strike.damage if strike.monster_id == first else -1)
	if damages != [WEAK_STRENGTH, WEAK_STRENGTH, WEAK_STRENGTH, WEAK_STRENGTH]:
		return "the companion's strikes on the first wild monster were %s, not 4, once a second" % [
			damages,
		]
	if _wild(state).hp_of(first) != 1:
		return "the companion's hits left the wild monster at %d HP, not 1" % [
			_wild(state).hp_of(first),
		]
	(state.feature(Features.HIDING) as HidingFeature).hidden.append_array(_wild(state).monsters)
	if not _strikes_over(state, 2 * CompanionAttackFeature.STRIKE_TICKS).is_empty():
		return "the companion struck a wild monster hiding in its tile"
	return _check_special(state, first, spots)


## The player fires their companion's special, hemmed in by the wild monsters on `spots`, all
## hiding, `first` the one with the lowest id: with nothing to strike it does nothing, and nor does
## a press for a slot without a player. Once they jump out, it fells `first` for its power, which
## faints for good, staying where it fell and saved as it is; it cools down, and once it's ready
## again it fells the next one.
func _check_special(state: GameState, first: int, spots: Array[Vector2i]) -> String:
	var wild: WildMonsterFeature = _wild(state)
	var nobody: Array[Command] = [Command.new(), Command.new(Command.NO_MOVE, true)]
	if not _specials_in(state, _fire()).is_empty() or not _specials_in(state, nobody).is_empty():
		return "a special struck a hiding wild monster, or fired for a slot without a player"
	(state.feature(Features.HIDING) as HidingFeature).hidden.clear()
	var felled: Array[SpecialStruck] = _specials_in(state, _fire())
	var damage: int = Fixed.scale(WEAK_STRENGTH, SPECIAL_POWER)
	if felled.size() != 1 or felled[0].monster_id != first or felled[0].damage != damage:
		return "the special didn't strike the first wild monster for its power"
	if not felled[0].felled or not wild.is_fainted(first) or wild.is_wild_monster(first):
		return "the special didn't fell the wild monster"
	var movement: MovementFeature = state.feature(Features.MOVEMENT) as MovementFeature
	if state.entity(first) == null or not movement.is_occupied(state, state.entity(first).tile):
		return "the fainted wild monster didn't stay where it fell, blocking walkers"
	return _check_special_cooldown(state, spots)


## After the special felled a wild monster in `state`: the wild monsters and the cooldown load back
## as saved, the special cools down for its cooldown, and once it's ready it fells the next one.
func _check_special_cooldown(state: GameState, spots: Array[Vector2i]) -> String:
	var specials: SpecialAttackFeature = state.feature(Features.SPECIALS) as SpecialAttackFeature
	var reloaded_state: GameState = _strike_state(spots)
	if not _reloads(state, reloaded_state, Features.WILD_MONSTERS):
		return "the fainted wild monster didn't load back as saved"
	if not _reloads(state, reloaded_state, Features.SPECIALS):
		return "the special's cooldown didn't load back as saved"
	if specials.cooldown_left(0) != SPECIAL_TICKS or not _specials_in(state, _fire()).is_empty():
		return "the special didn't cool down for its cooldown"
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	while specials.cooldown_left(0) > 1:
		var _waited: Array[SpecialStruck] = _specials_in(state, still)
	var second: int = _wild(state).monsters[0]
	var next: Array[SpecialStruck] = _specials_in(state, _fire())
	if next.size() != 1 or next[0].monster_id != second or not next[0].felled:
		return "the special, ready again, didn't fell the next wild monster"
	return _check_wild_attacks()


## Whether the feature `feature_id` of `state`, saved and loaded into `reloaded_state`, hashes the
## same.
static func _reloads(state: GameState, reloaded_state: GameState, feature_id: int) -> bool:
	var feature: Feature = state.feature(feature_id)
	var reloaded: Feature = reloaded_state.feature(feature_id)
	reloaded.load_values(reloaded_state, DataReader.new(feature.save_values()))
	return reloaded.hash_values() == feature.hash_values()


## One tick's commands with the player in slot 0 standing and firing their special.
static func _fire() -> Array[Command]:
	var firing: Array[Command] = [Command.new(Command.NO_MOVE, true)]
	return firing


## The specials that struck in one tick of `commands`.
static func _specials_in(state: GameState, commands: Array[Command]) -> Array[SpecialStruck]:
	Simulation.step(state, commands)
	var struck: Array[SpecialStruck] = []
	for event: RefCounted in state.events:
		if event is SpecialStruck:
			struck.append(event as SpecialStruck)
	return struck


## A weak wild monster strikes once a second, for its strength (#422): the companion next to it
## first, then, with the companion away, the player next to it, then, with the player away too,
## the trail tile next to it, which gives way on the strike that wears it through, not one before.
func _check_wild_attacks() -> String:
	var spots: Array[Vector2i] = [Vector2i.ZERO]
	var state: GameState = _strike_state(spots)
	state.companions[0] = WEAK
	var beside: Vector2i = Vector2i(1, 0)
	var player: Entity = state.add_entity(0, beside)
	var _joined: Array[WildMonsterStruck] = _wild_strikes_over(state, 1, Vector2i(-3, 0))
	var companion_id: int = (state.feature(Features.COMPANIONS) as CompanionFeature).companion_of(0)
	var struck: String = _struck_once(state, Vector2i(-1, 0), companion_id, "the companion")
	if struck.is_empty():
		struck = _struck_once(state, Vector2i(-3, 0), player.id, "the player")
	if not struck.is_empty():
		return struck
	player.tile = Vector2i(3, 0)
	var hits: int = Fixed.div_floor(
		WildAttackFeature.TILE_INTEGRITY + WEAK_STRENGTH - 1,
		WEAK_STRENGTH,
	)
	var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
	var gave_way: Callable = func() -> bool: return not trail.tiles.has(beside)
	struck = _wears_through(state, beside, hits, gave_way)
	if not struck.is_empty():
		return "the trail beside it: " + struck
	if not _wild_strikes_over(state, WildAttackFeature.STRIKE_TICKS, Vector2i(-3, 0)).is_empty():
		return "the wild monster struck with nothing next to it"
	return _check_ring_worn(state, player, hits)


## Why the wild monster in `state` didn't strike `tile` once a second and wear it through with
## `hits` strikes, `gone` turning true on the last one and not before, or "".
func _wears_through(state: GameState, tile: Vector2i, hits: int, gone: Callable) -> String:
	for hit: int in hits:
		var strikes: Array[WildMonsterStruck] = _wild_strikes_over(
			state,
			WildAttackFeature.STRIKE_TICKS,
			Vector2i(-3, 0),
		)
		if strikes.size() != 1 or strikes[0].target_id != 0 or strikes[0].tile != tile:
			return "not struck once in second %d" % hit
		if gone.call() != (hit == hits - 1):
			return "gave way after %d strikes, not %d" % [hit + 1, hits]
	return ""


## The player rings the wild monster in `state` and the ring waits for a totem (#423): encircled,
## the monster strikes only the ring's wall segment nearest to it, even with the player beside it,
## and the ring breaks on the `hits`-th strike that wears it through, not one before, and comes off
## the trail but for the tile the player stands on.
func _check_ring_worn(state: GameState, player: Entity, hits: int) -> String:
	var ring: Array[Vector2i] = Hex.ring(SMALL_RING)
	var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
	player.tile = ring[0]
	var _colored: bool = trail.color(ring[0], player.id)
	var _walked: Array[RefCounted] = FlowSteps.walk(state, ring.slice(1))
	var domination: DominationFeature = _domination(state)
	if domination.encircled.keys() != [player.id]:
		return "the ring around the attacking wild monster didn't wait for a totem"
	var walls: Array[Vector2i] = domination.ring_waiting(state, player.id)
	var wall: Vector2i = walls[RingShape.nearest(walls, Vector2i.ZERO)]
	var waiting: Dictionary = domination.encircled
	var broken: Callable = func() -> bool: return waiting.is_empty()
	var worn: String = _wears_through(state, wall, hits, broken)
	if not worn.is_empty():
		return "the waiting ring's nearest wall: " + worn
	for each: Vector2i in walls:
		if each != player.tile and trail.tiles.has(each):
			return "the broken ring's wall %s stayed on the trail" % each
	return ""


## Why the wild monster didn't strike `target_id` (`what`) exactly once over a second with the
## companion on `companion_tile`, or "".
func _struck_once(
		state: GameState,
		companion_tile: Vector2i,
		target_id: int,
		what: String,
) -> String:
	var ticks: int = WildAttackFeature.STRIKE_TICKS
	var strikes: Array[WildMonsterStruck] = _wild_strikes_over(state, ticks, companion_tile)
	if strikes.size() != 1 or strikes[0].target_id != target_id:
		return "the wild monster didn't strike %s once in a second" % what
	return ""


## The wild monsters' strikes over `ticks` ticks of the player standing still, with the player's
## companion put on `companion_tile` before each.
func _wild_strikes_over(
		state: GameState,
		ticks: int,
		companion_tile: Vector2i,
) -> Array[WildMonsterStruck]:
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var strikes: Array[WildMonsterStruck] = []
	for _tick: int in ticks:
		var companion: Entity = state.entity(companions.companion_of(0))
		if companion != null:
			companion.tile = companion_tile
		Simulation.step(state, still)
		for event: RefCounted in state.events:
			if event is WildMonsterStruck:
				strikes.append(event as WildMonsterStruck)
	return strikes


## A disc with a weak wild monster on each of `spots`, hiding, companions and their attacks and
## specials, and the wild monsters' attacks.
func _strike_state(spots: Array[Vector2i]) -> GameState:
	var region: Region = _outcome_state(WEAK, spots).region
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		WildMonsterFeature.new([], [], { WEAK: OUTCOME_HP }, { WEAK: WEAK_STRENGTH }),
		DominationFeature.new(),
		WildAttackFeature.new(),
		HidingFeature.new(),
		CompanionFeature.new(),
		CompanionAttackFeature.new(),
		SpecialAttackFeature.new({ WEAK: SPECIAL_POWER }, { WEAK: SPECIAL_TICKS }),
	]
	return GameState.new(region, 1, ordered)


## The companions' strikes over `ticks` ticks of the player standing still.
func _strikes_over(state: GameState, ticks: int) -> Array[CompanionStruck]:
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	var strikes: Array[CompanionStruck] = []
	for _tick: int in ticks:
		Simulation.step(state, still)
		for event: RefCounted in state.events:
			if event is CompanionStruck:
				strikes.append(event as CompanionStruck)
	return strikes


## Walks the player in slot 0 along `path` up to the start of its last step, which closes the
## ring, and places their totem on it the next tick (#423): the seal starts on the state's tick
## then.
func _close(state: GameState, path: Array[Vector2i]) -> void:
	var _walked: Array[RefCounted] = FlowSteps.walk(state, path.slice(0, path.size() - 1))
	var last: int = Hex.DIRECTIONS.find(path[path.size() - 1] - state.player(0).tile)
	Simulation.step(state, FlowSteps.command(last))
	Simulation.step(state, FlowSteps.totem())


## Steps the player in slot 0 standing until no ring seals, first placing their totem on a ring
## waiting for one (#423); returns every event raised.
func _settle(state: GameState) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	if not _domination(state).encircled.is_empty():
		Simulation.step(state, FlowSteps.totem())
		events.append_array(state.events)
	for _tick: int in MOST_SEAL_TICKS:
		if _domination(state).seals.is_empty():
			break
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		events.append_array(state.events)
	return events


## Every domination in `events`.
func _dominated(events: Array[RefCounted]) -> Array[WildMonsterDominated]:
	var dominated: Array[WildMonsterDominated] = []
	for event: RefCounted in events:
		if event is WildMonsterDominated:
			dominated.append(event as WildMonsterDominated)
	return dominated


func _toward(walker: Entity, next: Vector2i) -> int:
	return Hex.DIRECTIONS.find(next - walker.tile)


## The place_totem key places the player's totem on the ring they closed (#423), and while the ring
## seals, its tiles fill round the ring with the seal's progress, and the wall
## segment its player stands on wears a brace, reinforced (#234); then the wild monster doesn't
## blink out: it shrinks away calmly, and then it's gone, and so is the brace.
func _check_view(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree)
	var driver: GameDriver = FlowGame.held_driver(main)
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	# Drawn now, not left to whether a frame has passed yet.
	view.show_state()
	if view.figures.size() != 1:
		main.queue_free()
		return "the main scene doesn't show the wild monster's figure"
	var figure: HexPiece = view.figures.values()[0]
	var _walked: Array[RefCounted] = FlowSteps.walk(driver.state, FlowSteps.BASIC_RING)
	var result: String = _check_totem_button(main)
	if result.is_empty():
		result = _check_totem_key(main, driver.state)
	if result.is_empty():
		result = _check_filling(main, driver.state)
	if result.is_empty():
		result = _check_brace(main, driver.state)
	var braces: ReinforcementView = main.get_node("Instance/ReinforcementView") as ReinforcementView
	var brace: HexPiece = braces.figures.get(driver.state.player(0).tile)
	var _events: Array[RefCounted] = _settle(driver.state)
	view.show_state()
	braces.show_state()
	if result.is_empty() and _brace_left(braces, brace):
		result = "a brace stayed after the seal ended: %s" % [braces.figures.keys()]
	if result.is_empty() and (
		not view.figures.is_empty() or not is_instance_valid(figure) or not figure.is_inside_tree()
	):
		result = "the dominated figure didn't stay to shrink away"
	await tree.create_timer(WildMonsterView.FADE_SECONDS + 0.2).timeout
	if result.is_empty() and is_instance_valid(figure):
		result = "the dominated figure was still there after shrinking away"
	main.queue_free()
	await tree.process_frame
	return result


## On a touch screen, standing on a ring that waits for a totem, the totem's button shows its
## charges and isn't faded; a touch on it presses place_totem and never starts the touch stick, and
## lifting it lets go (#429).
func _check_totem_button(main: Node) -> String:
	var totem: TotemButton = main.get_node("Hud/TotemButton") as TotemButton
	var stick: TouchStick = main.get_node("Hud/TouchStick") as TouchStick
	totem.touch = true
	totem.lay_out_in(totem.get_viewport_rect().size)
	if (not totem.visible
			or totem.corner_text() != str(PlaceholderTotems.CHARGES)
			or not totem.usable()):
		return "the totem's button doesn't show its charges, usable, on a waiting ring"
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = totem.rect().get_center()
	touch.pressed = true
	totem.get_viewport().push_input(touch)
	var pressed: bool = Input.is_action_pressed("place_totem")
	var stick_held: bool = stick.is_held()
	var lift: InputEventScreenTouch = touch.duplicate() as InputEventScreenTouch
	lift.pressed = false
	totem.get_viewport().push_input(lift)
	if not pressed or stick_held or Input.is_action_pressed("place_totem"):
		return "a touch on the totem's button didn't press place_totem alone, or didn't let go"
	totem.touch = false
	return ""


## Pressing place_totem makes the local player's command place their totem, which starts the ring
## sealing; released, the next command places none.
func _check_totem_key(main: Node, state: GameState) -> String:
	var local: LocalInput = main.get_node("LocalInput") as LocalInput
	Input.action_press("place_totem")
	var placing: Array[Command] = [local.command(state)]
	Input.action_release("place_totem")
	var released: Command = local.command(state)
	Simulation.step(state, placing)
	if placing[0].totem != Command.PLACE_TOTEM or released.totem != Command.NO_TOTEM:
		return "the place_totem key gave the totems %d, then %d" % [
			placing[0].totem,
			released.totem,
		]
	if _domination(state).seals.is_empty():
		return "the totem placed with the key didn't start the ring sealing"
	return ""


## Halfway through the seal, about half the ring's tiles have the seal color, and the rest the
## trail's: the fill shows as a shape, not only a color.
func _check_filling(main: Node, state: GameState) -> String:
	var trails: TrailView = main.get_node("TrailView") as TrailView
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	var seal: RingSeal = _domination(state).seals.get(state.player(0).id)
	for _tick: int in Fixed.div_floor(seal.seal_ticks, 2):
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	trails.show_state()
	var sealed: int = 0
	for tile: Vector2i in seal.walls:
		if grid.tile_color_of(tile) == trails.seal_color:
			sealed += 1
	if sealed != TrailView.sealed_tiles(seal).size() or sealed == 0 or sealed == seal.walls.size():
		return "halfway through the seal, %d of the ring's %d tiles were filled" % [
			sealed,
			seal.walls.size(),
		]
	return ""


## Whether a brace is still shown, or `brace`, shown before, is still kept.
func _brace_left(braces: ReinforcementView, brace: HexPiece) -> bool:
	return not braces.figures.is_empty() or (brace != null and not brace.is_queued_for_deletion())


## The ring's player ends their walk on its wall, so that segment is reinforced: it, and only it,
## wears a brace, a ring shape rather than only a color (#68).
func _check_brace(main: Node, state: GameState) -> String:
	var braces: ReinforcementView = main.get_node("Instance/ReinforcementView") as ReinforcementView
	braces.show_state()
	var seal: RingSeal = _domination(state).seals.get(state.player(0).id)
	var braced: Array[Vector2i] = []
	braced.assign(braces.figures.keys())
	if braced != [state.player(0).tile] or braced != RingSealing.reinforced(state, seal):
		return "the braces stand on %s, not on the reinforced %s" % [
			braced,
			RingSealing.reinforced(state, seal),
		]
	var brace: MeshInstance3D = braces.figures[braced[0]].get_child(0) as MeshInstance3D
	if brace == null or not brace.mesh is TorusMesh:
		return "the brace isn't a ring"
	return ""


## A domination reaches the profile through the driver's ticked events, as in a session: it's taken
## over and, the first gain after a quiet spell, saved at once. Another slot's domination isn't this
## player's.
func _check_saved(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree, SAVE_PATH)
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	(main.get_node("LocalInput") as LocalInput).slot = 1
	var events: Array[RefCounted] = FlowSteps.walk(driver.state, FlowSteps.BASIC_RING)
	events.append_array(_settle(driver.state))
	driver.ticked.emit(driver.state.tick, events)
	var result: String = ""
	# The bus hands events out a frame later (#184), not while the tick runs.
	var bus: EventBus = main.get_node("EventBus") as EventBus
	if bus.queued.is_empty() or not holder.keeper.profile.dominated_monsters.is_empty():
		result = "the tick's events weren't queued for the next frame"
	bus.flush()
	if not holder.keeper.profile.dominated_monsters.is_empty():
		result = "another slot's domination went into this player's profile"
	(main.get_node("LocalInput") as LocalInput).slot = 0
	driver.ticked.emit(driver.state.tick, events)
	(main.get_node("EventBus") as EventBus).flush()
	var species: Array[String] = []
	for monster: DominatedMonster in SaveStore.load_profile(SAVE_PATH).dominated_monsters:
		species.append(monster.species)
	var expected: String = _dominated_species(events)
	var saved_one: bool = species.size() == 1 and species[0] == expected
	if result.is_empty() and (expected.is_empty() or not saved_one):
		result = "the dominated %s wasn't saved into the profile: %s" % [expected, species]
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## The species of the first wild monster dominated in `events`, or "".
func _dominated_species(events: Array[RefCounted]) -> String:
	var dominated: Array[WildMonsterDominated] = _dominated(events)
	return dominated[0].species if not dominated.is_empty() else ""


## Species (#133): a spot its region piece names always has that species (the arena's boss is a
## storm finch); the others roll from their blueprint's list, the same way for the same seed, every
## species on the list turning up over enough seeds, and the domination carries it.
func _check_species() -> String:
	var rolled: Dictionary[String, bool] = {}
	for seed_value: int in 24:
		var arena: GameState = InstanceBlueprints.create(InstanceBlueprints.ARENA, seed_value)
		if _wild(arena).species_of(_wild(arena).monsters[0]) != "storm_finch":
			return "seed %d's arena boss isn't the storm finch it names" % seed_value
		var basic: String = _first_species(InstanceBlueprints.basic(seed_value))
		if basic != _first_species(InstanceBlueprints.basic(seed_value)):
			return "seed %d placed two different species" % seed_value
		rolled[basic] = true
	var listed: Array = InstanceBlueprints.WILD_SPECIES[InstanceBlueprints.BASIC].keys()
	if rolled.size() != listed.size():
		return "the basic instance's spots rolled %s, not every one of %s" % [rolled.keys(), listed]
	var state: GameState = InstanceBlueprints.basic(1)
	var events: Array[RefCounted] = FlowSteps.walk(state, FlowSteps.BASIC_RING)
	events.append_array(_settle(state))
	if _dominated_species(events) != _first_species(InstanceBlueprints.basic(1)):
		return "the domination didn't carry the dominated monster's species"
	return _check_wounded()


## A legend can mark a wild monster wounded (#389): it starts at WOUNDED_HP of its full HP, never
## below 1, while the one beside it starts at full.
func _check_wounded() -> String:
	var tiles: String = "# W\n\n## Tiles\n\n```\nw 1 t\n```\n\n## Legend\n\n"
	tiles += "- `w`: a wild monster, always moss_toad, wounded\n"
	tiles += "- `t`: a wild monster, always moss_toad\n"
	var region: Region = RegionDocument.parse(tiles)
	var marked: int = 0
	for spot: WildSpot in region.wild_spots.values():
		marked += 1 if spot.wounded else 0
	if not region.problem.is_empty() or marked != 1:
		return "a legend didn't mark its wild monster wounded: " + region.problem
	var hp: Dictionary[String, int] = { "moss_toad": OUTCOME_HP }
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		WildMonsterFeature.new([], [], hp, { "moss_toad": WEAK_STRENGTH }),
	]
	var state: GameState = GameState.new(region, 1, ordered)
	var wild: WildMonsterFeature = _wild(state)
	var weak: int = maxi(Fixed.scale(OUTCOME_HP, WildMonsterFeature.WOUNDED_HP), 1)
	var expected: Array[int] = [weak, OUTCOME_HP]
	var started: Array[int] = []
	for monster: int in wild.monsters:
		started.append(wild.hp_of(monster))
	if started != expected:
		return "the wounded and the whole wild monster started at %s HP, not %s" % [
			started,
			expected,
		]
	return _check_hiding()


## The species of the first wild monster in `state`.
func _first_species(state: GameState) -> String:
	return _wild(state).species_of(_wild(state).monsters[0])


func _wild(state: GameState) -> WildMonsterFeature:
	return state.feature(Features.WILD_MONSTERS) as WildMonsterFeature


func _trails(state: GameState) -> TrailFeature:
	return state.feature(Features.TRAIL) as TrailFeature


func _domination(state: GameState) -> DominationFeature:
	return state.feature(Features.DOMINATION) as DominationFeature
