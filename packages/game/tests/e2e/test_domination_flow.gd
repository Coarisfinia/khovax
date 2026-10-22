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
## the small ring holds; standing on any other segment of it, they don't, and it breaks. A ring
## dominating a monster its region marks as a quest target (#625) names the target.
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
## good where it fell, and then it cools down. The felled monster drops crafting materials (#629):
## every player in the instance rolls their own on its species' loot table, from a stream a save
## resumes, and this machine's player's own roll bursts from it and lands in their profile, while
## another player's doesn't. A wild monster strikes once a second too (#422): the
## companion next to it first, then the player, then the trail, whose tile gives way once worn
## through; encircled, it strikes only its ring's wall, and wearing through it breaks the ring.
## With the type chart on (#626), the strikes between monsters follow it by each strike's own type;
## switched off, they deal their plain damage.
## A companion that faints is swapped for the next monster its player carries (#597).
## With spikes in their trap slot (#692), put there by a request from their outbox (#818) that the
## world keeps in their store, the player's ring hurts the wild monster pushing on it once a second
## for the spikes' damage, while it waits for a totem and while it seals, never below 1 HP; without,
## it doesn't.
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
const COMPANION: String = "ombulumo"
## The outcome tests' species, in a disc region of radius OUTCOME_RADIUS: a weak and a strong one,
## both at full HP.
const OUTCOME_RADIUS: int = 4
const WEAK: String = "weak"
const STRONG: String = "strong"
const OUTCOME_HP: int = 100
const WEAK_STRENGTH: int = 40
## A companion's HP in the strike checks: enough to outlast several weak wild monsters' hits
## while its own strikes are counted, and to fall within the fall check's seconds (#456).
const COMPANION_HP: int = WEAK_STRENGTH * 100
const STRONG_STRENGTH: int = 400
## The weak species' special: three times its strength, more than a weak monster's HP, and its
## cooldown.
const SPECIAL_POWER: int = 3000
const SPECIAL_TICKS: int = 50
## What a felled weak monster drops (#629): its loot table always rolls this.
const HIDE_LOOT: Dictionary[String, int] = { "hide": 2 }
## The type checks' strikes, by the strike's type and the struck species (_type_chart), and how
## hard each hits in thousandths (#626): a Greater strike on a double weakness ×4, a Lesser one
## ×1.5 twice, one on its own family's Greater type ×0.5, a strong and a weak one multiplying, and
## a strike on a species without types ×1.
const TYPE_FACTORS: Dictionary[String, int] = {
	"titan double": 4000,
	"might double": 2250,
	"mana greater": 500,
	"growth mixed": 1125,
	"titan none": 1000,
}
## A small ring and a big one around the disc's middle, by their radius.
const SMALL_RING: int = 1
const BIG_RING: int = 3
## The HP the enrage check wears its monster down to before enraging it further.
const WORN: int = 10
## No second player on the outcome's wall.
const NO_HELPER: int = -1
## The spikes' damage in the spikes check (#692), and their gear's id.
const SPIKES_DAMAGE: int = 7
const SPIKES: String = "test_spikes"
## No request to change the trap (_spiked_over).
const NO_TRAP_CHANGE: int = -1
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
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 0)
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
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
🦔
```

## Legend

- `🦔`: "
	piece += LegendMeaning.HIDING
	var shrubs: Region = InstanceBlueprints.read_region(piece + "shrubs
")
	if not shrubs.problem.is_empty() or shrubs.wild_monsters != [Vector2i.ZERO]:
		return "a wild monster hiding in shrubs doesn't read: " + shrubs.problem
	if not HidingFeature.hides_at(shrubs, Vector2i.ZERO):
		return "the wild monster said to hide in shrubs isn't on shrubs"
	if InstanceBlueprints.read_region(piece + "ground
").problem.is_empty():
		return "a legend hid a wild monster in plain ground"
	return _check_standing_on(piece.trim_suffix(LegendMeaning.HIDING))


## A named wild monster can stand on a tile kind (#452): the spot is that kind, and a legend naming
## no species or no kind is refused.
func _check_standing_on(piece: String) -> String:
	var named: String = "a wild monster, always ombulumo, on sand\n"
	var sand: Region = InstanceBlueprints.read_region(piece + named)
	var on_sand: bool = sand.terrain.get(Vector2i.ZERO) == "sand"
	var spots: int = sand.placed(WildSpotPlacements.KIND).size()
	if not sand.problem.is_empty() or spots != 1 or not on_sand:
		return "a wild monster standing on sand doesn't read: " + sand.problem
	var broken_meanings: Array[String] = [
		"a wild monster, always, on sand",
		"a wild monster, always ombulumo, on nowhere",
	]
	for broken: String in broken_meanings:
		if InstanceBlueprints.read_region(piece + broken + "\n").problem.is_empty():
			return "a legend read a wild monster without its species or its tile kind: " + broken
	return _check_companion_strikes()


## Every ring tile but the last: the walk passes right by the wild monster and dominates nothing.
func _check_open_ring() -> String:
	var state: GameState = FlowSteps.basic(42)
	var ring: Array[Vector2i] = FlowSteps.BASIC_RING
	var _events: Array[RefCounted] = FlowSteps.walk(state, ring.slice(0, ring.size() - 1))
	# Both wild monsters stay: the rolled one and the beach's wounded toad (#448).
	if _wild(state).monsters.size() != 2 or not _domination(state).seals.is_empty():
		return "an open ring dominated the wild monster or started sealing"
	if not _domination(state).encircled.is_empty():
		return "an open ring encircled the wild monster"
	return ""


## A closed ring around another tile leaves the wild monster alone, and the trail keeps growing.
func _check_other_ring() -> String:
	var state: GameState = FlowSteps.basic(42)
	var _events: Array[RefCounted] = FlowSteps.walk(state, OTHER_RING)
	var trail: Trail = _trails(state).shared
	# The rolled one and the beach's toad (#448) both stay.
	if _wild(state).monsters.size() != 2 or trail.tiles.size() != OTHER_RING.size() + 1:
		return "a ring around another tile dominated the wild monster or reset the trail"
	if not _domination(state).seals.is_empty() or not _domination(state).encircled.is_empty():
		return "a ring around no wild monster started sealing or waited for a totem"
	return _check_waits_for_totem()


## The full ring doesn't seal by itself (#423): it waits for a totem, the wild monster encircled. A
## totem placed one step off the ring does nothing; back on it, the totem spends one
## charge and the ring seals, and holding it there spends no more. A player out of charges places
## none.
func _check_waits_for_totem() -> String:
	var state: GameState = FlowSteps.basic(42)
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
	var state: GameState = FlowSteps.basic(42)
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
	var state: GameState = FlowSteps.basic(42)
	var monster_id: int = _wild(state).monsters[0]
	_close(state, FlowSteps.BASIC_RING)
	var closed: int = state.tick
	var player: Entity = state.player(0)
	var seal: RingSeal = _domination(state).seals.get(player.id)
	if seal == null or state.entity(monster_id) == null or seal.monsters != [monster_id]:
		return "the totem on the closed ring didn't start sealing the wild monster in"
	var expected_ticks: int = RingSealing.SEAL_BASE_TICKS + Fixed.div_floor(
		RingSealing.pressure(state, _wild(state), _health(state), monster_id),
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
## the domination's DominationLoot gives exactly the slots that earned any (every species has a
## loot table, #943). A player who only braced the wall for a second earns nothing.
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
	if looted != earning:
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
	var again: GameState = FlowSteps.basic(42)
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
		FlowSteps.BASIC,
		2,
	)
	CompanionParty.bring(world, FlowSteps.parties([[COMPANION]]))
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
	var basic: GameState = world.instances[FlowSteps.BASIC]
	if _domination(basic).seals.is_empty():
		return "the world's ring wasn't sealing when saved"
	var refused: String = _check_seal_refused(world)
	if not refused.is_empty():
		return refused
	var resumed: World = WorldSave.parse(WorldSave.to_text(world), BlueprintSource.new())
	if not resumed.problem.is_empty() or resumed.state_hash() != world.state_hash():
		return "the world saved mid-seal didn't resume as it was: " + resumed.problem
	for _tick: int in MOST_SEAL_TICKS:
		world.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		resumed.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		if resumed.state_hash() != world.state_hash():
			return "the resumed seal went another way at tick %d" % world.tick
	# Only the beach's wounded toad (#448) is left.
	if _wild(resumed.instances[FlowSteps.BASIC]).monsters.size() != 1:
		return "the resumed seal didn't dominate the wild monster"
	return ""


## A world saved while its basic instance's ring waits for a totem resumes as it was, and a save
## whose waiting ring names its monster twice is refused.
func _check_wait_saved(world: World) -> String:
	var resumed: World = WorldSave.parse(WorldSave.to_text(world), BlueprintSource.new())
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
	var basic: GameState = world.instances[FlowSteps.BASIC]
	var companions: CompanionFeature = basic.feature(CompanionFeature.ID) as CompanionFeature
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
	other["dominator"] = world.player(1).id
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
		if instance["name"] != FlowSteps.BASIC:
			continue
		for feature: Dictionary in instance["state"]["features"]:
			if feature["id"] == DominationFeature.ID:
				return feature["values"]
	return { "seals": [], "waiting": [] }


## Two allies close one ring together (#87): the first player walks half of it, then the second
## the rest, and the second's step closes it. The second places their totem on it, and the
## domination still goes to the first, the lowest slot among those who colored its wall (owner,
## #86). Then the ring is off the trail, but the trail leading up to it stays, and each player
## colors the tile they stand on.
func _check_together() -> String:
	var state: GameState = FlowSteps.basic(42, 2)
	FlowSteps.drop_beach_toad(state)
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
	# The second stands on their ally's ring: the rule lets them place their totem, and their
	# button says so (#931).
	if not _domination(state).can_place_totem(state, second.id):
		return "the rule doesn't let the second place their totem on their ally's ring"
	if not _usable(TotemButton.new(), state, 1):
		return "the second's totem button is faded on their ally's ring, where their totem works"
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
	if enraged.is_empty():
		enraged = _check_enraged_chase()
	if enraged.is_empty():
		enraged = _check_enraged_strikes()
	if enraged.is_empty():
		enraged = _check_target_dominated()
	if enraged.is_empty():
		enraged = _check_spikes()
	return enraged if not enraged.is_empty() else _check_moves_away()


## A ring dominating a wild monster its region marks as a quest target (#625) names the target in
## the domination, so the dominator's quest asking for it counts it.
func _check_target_dominated() -> String:
	var state: GameState = _outcome_state(WEAK, [Vector2i.ZERO], "old_toad")
	var ring: Array[Vector2i] = Hex.ring(SMALL_RING)
	var _player: Entity = state.add_entity(0, ring[0])
	_close(state, ring.slice(1))
	var events: Array[RefCounted] = _step_off(state)
	events.append_array(_settle(state))
	var dominated: Array[WildMonsterDominated] = _dominated(events)
	if dominated.size() != 1 or dominated[0].target != "old_toad":
		return "dominating the quest target old_toad didn't name it in its domination"
	return ""


## A weak monster in a small ring (#692): while the ring waits for a totem, it isn't hurt as long as
## the player's trap is empty, and from the tick a request puts their spikes into it (#818), kept
## in their world store, it's hurt once in STRIKE_TICKS for their damage. Worn down to 2 HP, it's
## hurt once more while the ring seals, and then holds at 1 HP.
func _check_spikes() -> String:
	var spikes: Array[Feature] = [
		SpikesFeature.new({ SpikesFeature.code_of(SPIKES): SPIKES_DAMAGE }),
	]
	var state: GameState = _outcome_state(WEAK, [Vector2i.ZERO], "", spikes)
	var ring: Array[Vector2i] = Hex.ring(SMALL_RING)
	var _player: Entity = state.add_entity(0, ring[0])
	var _walked: Array[RefCounted] = FlowSteps.walk(state, ring.slice(1))
	var monster: int = _wild(state).monsters[0]
	if _domination(state).encircled.is_empty():
		return "the spikes check's ring doesn't wait for a totem"
	var bare: Array[SpikesStruck] = _spiked_over(state, 2 * SpikesFeature.STRIKE_TICKS)
	var spiked: Array[SpikesStruck] = _spiked_over(
		state,
		SpikesFeature.STRIKE_TICKS,
		false,
		SpikesFeature.code_of(SPIKES),
	)
	if SpikesFeature.trap_of(state.stored(0, SpikesFeature.ID)) != SpikesFeature.code_of(SPIKES):
		return "the request didn't put the spikes into the player's trap in their store"
	var hp: int = _hp(state, monster)
	if not bare.is_empty() or spiked.size() != 1 or hp != OUTCOME_HP - SPIKES_DAMAGE:
		return "spikes hurt %d times without, %d with, to %d HP" % [bare.size(), spiked.size(), hp]
	if spiked[0].monster_id != monster or spiked[0].damage != SPIKES_DAMAGE:
		return "the spikes didn't hurt the ringed monster for their damage"
	_wild(state).wound(state, monster, hp - 2)
	# The totem's tick counts too: the ring seals from the domination's step, before the spikes'.
	var sealing: Array[SpikesStruck] = _spiked_over(state, 1, true)
	while not _domination(state).seals.is_empty() and sealing.size() < 2:
		sealing.append_array(_spiked_over(state, 1))
	if sealing.size() != 2 or _hp(state, monster) != 1:
		return "a sealing monster was hurt %d times, to %d HP, not twice to 1" % [
			sealing.size(),
			_hp(state, monster),
		]
	return ""


## The spikes' hurts over `ticks` ticks of the player in slot 0 standing, placing their totem with
## `placing`, the first tick's command carrying a request (#818) to put the gear with the code
## `trap` into their trap slot, unless it's NO_TRAP_CHANGE.
func _spiked_over(
		state: GameState,
		ticks: int,
		placing: bool = false,
		trap: int = NO_TRAP_CHANGE,
) -> Array[SpikesStruck]:
	var still: Array[Command] = FlowSteps.totem() if placing else FlowSteps.command(Command.NO_MOVE)
	var first: Array[Command] = FlowSteps.totem() if placing else FlowSteps.command(Command.NO_MOVE)
	if trap != NO_TRAP_CHANGE:
		# The first id a profile's outbox draws (Outbox, #942).
		first[0].request = ShortId.code(ShortId.of_code(1))
		first[0].request_kind = OutboxEntry.TRAP
		first[0].request_data = trap
	var hurts: Array[SpikesStruck] = []
	for tick: int in ticks:
		Simulation.step(state, first if tick == 0 else still)
		for event: RefCounted in state.events:
			if event is SpikesStruck:
				hurts.append(event as SpikesStruck)
	return hurts


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


## Enraged (#961), a wild monster is faster: each stack of rage shortens its pace. It steps toward
## the nearest of two players once in its pace, ending next to them, and stays there; a calm one
## where a ring could enclose it stands.
func _check_enraged_chase() -> String:
	var spots: Array[Vector2i] = [Vector2i.ZERO, Vector2i(-2, 2)]
	var state: GameState = _outcome_state(STRONG, spots)
	var wild: WildMonsterFeature = _wild(state)
	var chaser: int = wild.monsters[0]
	wild.enrage(state, chaser, 0)
	var _near: Entity = state.add_entity(0, Vector2i(3, 0))
	var _far: Entity = state.add_entity(1, Vector2i(0, -4))
	var paces: Array[int] = []
	for rage: int in WildMonsterFeature.MOST_RAGE + 1:
		paces.append(WildMonsterFeature.paced(WildMonsterFeature.STEP_TICKS, rage))
	for rage: int in WildMonsterFeature.MOST_RAGE:
		if paces[rage + 1] >= paces[rage]:
			return "rage doesn't make a wild monster faster: its paces are %s" % [paces]
	var still: Array[Command] = FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE])
	for expected: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 0)]:
		for _tick: int in paces[1]:
			Simulation.step(state, still)
		var calm: Vector2i = state.entity(wild.monsters[1]).tile
		var tiles: Array[Vector2i] = [state.entity(chaser).tile, calm]
		if tiles != [expected, spots[1]]:
			return "the enraged and the calm monster stand on %s, not %s and %s" % [
				tiles,
				expected,
				spots[1],
			]
	return ""


## Enraged (#961), a free wild monster with a companion and a player next to it strikes the player
## first, once in its pace.
func _check_enraged_strikes() -> String:
	var spots: Array[Vector2i] = [Vector2i.ZERO]
	var state: GameState = _strike_state(spots)
	FlowSteps.carry(state, 0, [WEAK])
	var player: Entity = state.add_entity(0, Vector2i(1, 0))
	var monster: int = _wild(state).monsters[0]
	_wild(state).enrage(state, monster, 0)
	# The companion joins its player first, away from the monster.
	var _joined: Array[WildMonsterStruck] = _wild_strikes_over(state, 1, Vector2i(-3, 0))
	var pace: int = WildMonsterFeature.paced(WildAttackFeature.STRIKE_TICKS, 1)
	var strikes: Array[WildMonsterStruck] = _wild_strikes_over(state, pace, Vector2i(-1, 0))
	if strikes.size() != 1 or strikes[0].target_id != player.id:
		return "the enraged monster didn't strike the player first, once in %d ticks" % pace
	return ""


## A RingBroken event for a ring that had only `monster` inside.
func _broken_around(monster: int) -> RingBroken:
	var inside: Array[int] = [monster]
	var walls: Array[Vector2i] = []
	return RingBroken.new(0, 0, Vector2i.ZERO, walls, inside)


## Saves the HP with `monster` at WORN HP and loads it and the wild monsters back: its rage must
## survive.
func _wear_down(state: GameState, monster: int) -> String:
	var saved: Dictionary = _health(state).save_values()
	var hurt: Array[int] = [monster]
	var damage: Array[int] = [OUTCOME_HP - WORN]
	saved["hurt"] = hurt
	saved["damage"] = damage
	var healths: DataReader = DataReader.new(saved)
	_health(state).load_values(state, healths)
	var wild: WildMonsterFeature = _wild(state)
	var restored: DataReader = DataReader.new(wild.save_values())
	wild.load_values(state, restored)
	if healths.failed() or restored.failed():
		return "the HP or the wild monsters didn't load: %s" % (healths.problem + restored.problem)
	if wild.rage_of(monster) != 1 or _hp(state, monster) != WORN:
		return "the monster's rage or HP didn't survive a save"
	return ""


## Every further ring the monster breaks adds a stack, up to the most it takes, each making it
## stronger still and healing EnrageFeature.HEAL of its full HP, never past it: it's worn down to
## WORN HP first (through a save, as nothing hurts monsters yet). Its rage is saved too.
func _enraged_further(state: GameState, monster: int) -> String:
	var worn: String = _wear_down(state, monster)
	if not worn.is_empty():
		return worn
	var wild: WildMonsterFeature = _wild(state)
	var enrage: EnrageFeature = state.feature(EnrageFeature.ID) as EnrageFeature
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
		if wild.rage_of(monster) != rage or not stronger or _hp(state, monster) != healed:
			return "broken ring %d left rage %d, strength %d, HP %d" % [
				stack,
				wild.rage_of(monster),
				wild.strength_of(monster),
				_hp(state, monster),
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


## A disc with monsters of `species` on `spots`, each the quest target `target` when it's given
## (#625), and no player yet, then the `extra` features.
func _outcome_state(
		species: String,
		spots: Array[Vector2i],
		target: String = "",
		extra: Array[Feature] = [],
) -> GameState:
	var region: Region = Region.disc(OUTCOME_RADIUS)
	region.wild_monsters = spots
	var named: String = WildSpot.NAMED + species
	if not target.is_empty():
		named += ", " + WildSpot.TARGETED + target
	for spot: Vector2i in spots:
		region.add_placement(WildSpotPlacements.KIND, spot, named)
	var hp: Dictionary[String, int] = { WEAK: OUTCOME_HP, STRONG: OUTCOME_HP }
	var strength: Dictionary[String, int] = { WEAK: WEAK_STRENGTH, STRONG: STRONG_STRENGTH }
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(hp),
		WildMonsterFeature.new([], [], strength),
		DominationFeature.new(),
		EnrageFeature.new(),
	]
	ordered.append_array(extra)
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
	FlowSteps.carry(state, 0, [WEAK])
	var _player: Entity = state.add_entity(0, Vector2i(-2, 0))
	if not _strikes_over(state, 1).is_empty():
		return "the companion struck before it stood next to a wild monster"
	var companion_id: int = (state.feature(CompanionFeature.ID) as CompanionFeature).companion_of(0)
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
	if _hp(state, first) != 1:
		return "the companion's hits left the wild monster at %d HP, not 1" % [
			_hp(state, first),
		]
	(state.feature(HidingFeature.ID) as HidingFeature).hidden.append_array(_wild(state).monsters)
	if not _strikes_over(state, 2 * CompanionAttackFeature.STRIKE_TICKS).is_empty():
		return "the companion struck a wild monster hiding in its tile"
	var result: String = _check_no_special(spots, hemmed)
	return result if not result.is_empty() else _check_special(state, first, spots)


## The player fires their companion's special, hemmed in by the wild monsters on `spots`, all
## hiding, `first` the one with the lowest id: with nothing to strike it does nothing, and nor does
## a press for a slot without a player. Once they jump out, it fells `first` for its power, even
## with the player focused, which faints for good, staying where it fell and saved as it is; it
## cools down, and once it's ready again it fells the one the player focuses (#436).
func _check_special(state: GameState, first: int, spots: Array[Vector2i]) -> String:
	var wild: WildMonsterFeature = _wild(state)
	var nobody: Array[Command] = [Command.new(), Command.new(Command.NO_MOVE, true)]
	if not _specials_in(state, _fire()).is_empty() or not _specials_in(state, nobody).is_empty():
		return "a special struck a hiding wild monster, or fired for a slot without a player"
	(state.feature(HidingFeature.ID) as HidingFeature).hidden.clear()
	# A focus that isn't a wild monster (#436), here the player, leaves the usual target.
	var player_focus: Array[Command] = [
		Command.new(Command.NO_MOVE, true, Command.NO_TOTEM, state.player(0).id),
	]
	var felled: Array[SpecialStruck] = _specials_in(state, player_focus)
	var damage: int = Fixed.scale(WEAK_STRENGTH, SPECIAL_POWER)
	if felled.size() != 1 or felled[0].monster_id != first or felled[0].damage != damage:
		return "the special didn't strike the first wild monster for its power"
	if not felled[0].felled or not wild.is_fainted(first) or wild.monsters.has(first):
		return "the special didn't fell the wild monster"
	# Its look (#431): the damage rises from the monster, and says in words that it fainted.
	var shown: String = DamageNumbersView.text_of(felled[0])
	if shown != "-%d\n%s" % [damage, DamageNumbersView.FAINTED_TEXT]:
		return "the special's strike shows %s, not its damage and that it fainted" % shown
	# With the damage numbers off (#764), only that it fainted.
	if DamageNumbersView.text_of(felled[0], false) != DamageNumbersView.FAINTED_TEXT:
		return "with the damage numbers off, the special's strike still shows its damage"
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	if state.entity(first) == null or not movement.is_occupied(state, state.entity(first).tile):
		return "the fainted wild monster didn't stay where it fell, blocking walkers"
	var result: String = _check_harvest(state, first)
	return result if not result.is_empty() else _check_special_cooldown(state, spots)


## A companion whose species has no special, hemmed in on `hemmed` by the wild monsters on `spots`,
## which it could strike: a press fires nothing, and the special's button agrees, faded (#931); with
## its special back, the button shows usable.
func _check_no_special(spots: Array[Vector2i], hemmed: Vector2i) -> String:
	var state: GameState = _strike_state(spots)
	FlowSteps.carry(state, 0, [WEAK])
	var _player: Entity = state.add_entity(0, Vector2i(-2, 0))
	# The companion joins on the tick after its player arrives.
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	var companion_id: int = (state.feature(CompanionFeature.ID) as CompanionFeature).companion_of(0)
	state.entity(companion_id).tile = hemmed
	var specials: SpecialAttackFeature = (
		state.feature(SpecialAttackFeature.ID) as SpecialAttackFeature
	)
	var power: int = specials.powers[WEAK]
	var _dropped: bool = specials.powers.erase(WEAK)
	if _usable(SpecialButton.new(), state, 0) or specials.can_fire(state, 0):
		return "the special's button or the rule says a species without a special can fire one"
	var fired: bool = not _specials_in(state, _fire()).is_empty()
	specials.powers[WEAK] = power
	if fired:
		return "a companion whose species has no special fired one"
	if not _usable(SpecialButton.new(), state, 0):
		return "the special's button is faded with a wild monster next to the companion to strike"
	return ""


## Whether `button`, on a session showing `state` to the player in `slot`, shows usable; it and the
## session are freed.
static func _usable(button: ActionButton, state: GameState, slot: int) -> bool:
	var session: Session = Session.new()
	session.world = World.new(BlueprintSource.new(), 0, "")
	session.world.instances[session.local_instance_name()] = state
	session.input = LocalInput.new()
	session.input.slot = slot
	button.driver = session
	var usable: bool = button.usable()
	button.free()
	session.input.free()
	session.free()
	return usable


## The wild monster `first`, felled in `state`'s last tick, dropped its materials where it lies
## (#629): the only player's roll on its species' table.
func _check_harvest(state: GameState, first: int) -> String:
	var dropped: Array[Harvested] = []
	for event: RefCounted in state.events:
		if event is Harvested:
			dropped.append(event as Harvested)
	if dropped.size() != 1 or dropped[0].monster_id != first:
		return "the felled wild monster dropped %d lots of materials, not one" % dropped.size()
	var harvested: Harvested = dropped[0]
	var rolled: bool = harvested.loot.keys() == [0]
	if not rolled or ChestView.loot_text(harvested.loot[0]) != ChestView.loot_text(HIDE_LOOT):
		return "the felled wild monster dropped %s, not the player's %s" % [
			harvested.loot,
			HIDE_LOOT,
		]
	if harvested.tile != state.entity(first).tile or harvested.species != WEAK:
		return "the materials didn't drop where the felled wild monster lies"
	return ""


## After the special felled a wild monster in `state`: the wild monsters and the cooldown load back
## as saved, the special cools down for its cooldown, and once it's ready it fells the next one.
func _check_special_cooldown(state: GameState, spots: Array[Vector2i]) -> String:
	var specials: SpecialAttackFeature = (
		state.feature(SpecialAttackFeature.ID) as SpecialAttackFeature
	)
	var reloaded_state: GameState = _strike_state(spots)
	# The wild monsters' HP first: they check theirs against it as they load (#835).
	var hurt: Array[int] = []
	var damage: Array[int] = []
	for monster: int in _wild(state).monsters + _wild(state).fainted:
		hurt.append(monster)
		damage.append(_health(state).max_hp_of(state, monster) - _hp(state, monster))
	var healths: DataReader = DataReader.new({ "hurt": hurt, "damage": damage })
	_health(reloaded_state).load_values(reloaded_state, healths)
	if healths.failed():
		return "the wild monsters' HP didn't load back: " + healths.problem
	if not _reloads(state, reloaded_state, WildMonsterFeature.ID):
		return "the fainted wild monster didn't load back as saved"
	if not _reloads(state, reloaded_state, SpecialAttackFeature.ID):
		return "the special's cooldown didn't load back as saved"
	if not _reloads(state, reloaded_state, HarvestFeature.ID):
		return "the harvest's rolls didn't load back as saved"
	if specials.cooldown_left(0) != SPECIAL_TICKS or not _specials_in(state, _fire()).is_empty():
		return "the special didn't cool down for its cooldown"
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	while specials.cooldown_left(0) > 1:
		var _waited: Array[SpecialStruck] = _specials_in(state, still)
	var aimed: int = _focusable(state)
	if aimed == 0:
		return "the special's check needs two wild monsters the companion can strike"
	var focused: Array[Command] = [Command.new(Command.NO_MOVE, true, Command.NO_TOTEM, aimed)]
	var next: Array[SpecialStruck] = _specials_in(state, focused)
	if next.size() != 1 or next[0].monster_id != aimed or not next[0].felled:
		return "the special, ready again, didn't fell the focused wild monster (#436)"
	return _check_wild_attacks()


## A wild monster the companion in `state` can strike other than the one it strikes unfocused, so a
## focus on it (#436) shows; 0 if there is none.
func _focusable(state: GameState) -> int:
	var wild: WildMonsterFeature = _wild(state)
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var tile: Vector2i = state.entity(companions.companion_of(0)).tile
	var usual: int = CompanionAttackFeature.target_next_to(state, wild, tile)
	for monster: int in wild.monsters:
		if monster != usual and CompanionAttackFeature.can_strike(state, wild, tile, monster):
			return monster
	return 0


## Whether the feature `feature_id` of `state`, saved and loaded into `reloaded_state`, hashes the
## same.
static func _reloads(state: GameState, reloaded_state: GameState, feature_id: String) -> bool:
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
	FlowSteps.carry(state, 0, [WEAK])
	var beside: Vector2i = Vector2i(1, 0)
	var player: Entity = state.add_entity(0, beside)
	var _joined: Array[WildMonsterStruck] = _wild_strikes_over(state, 1, Vector2i(-3, 0))
	var companion_id: int = (state.feature(CompanionFeature.ID) as CompanionFeature).companion_of(0)
	var struck: String = _struck_once(state, Vector2i(-1, 0), companion_id, "the companion")
	if struck.is_empty():
		struck = _check_companion_falls(state, Vector2i(-1, 0), companion_id)
	if struck.is_empty():
		struck = _struck_once(state, Vector2i(-3, 0), player.id, "the player")
	if not struck.is_empty():
		return struck
	player.tile = Vector2i(3, 0)
	var hits: int = Fixed.div_floor(
		WildAttackFeature.TILE_INTEGRITY + WEAK_STRENGTH - 1,
		WEAK_STRENGTH,
	)
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	var gave_way: Callable = func() -> bool: return not trail.tiles.has(beside)
	struck = _wears_through(state, beside, hits, gave_way)
	if not struck.is_empty():
		return "the trail beside it: " + struck
	if not _wild_strikes_over(state, WildAttackFeature.STRIKE_TICKS, Vector2i(-3, 0)).is_empty():
		return "the wild monster struck with nothing next to it"
	struck = _check_ring_worn(state, player, hits)
	return struck if not struck.is_empty() else _check_type_effectiveness()


## Type effectiveness (#626): the chart's factors, a dual type's two multiplying. With the chart
## on, the weak species' strikes follow it by their own types, not its type: its auto attack, a
## Lesser Titan strike, hits a wild monster of its own Lesser Nature type ×1.5, and so does a wild
## monster's on the companion; its special, a Greater Titan strike, ×2. Switched off, they deal
## their plain damage.
func _check_type_effectiveness() -> String:
	var chart: TypeEffectivenessFeature = _type_chart()
	for strike: String in TYPE_FACTORS:
		var factor: int = chart.factor(strike.get_slice(" ", 0), strike.get_slice(" ", 1))
		if factor != TYPE_FACTORS[strike]:
			return "a %s strike hits ×%d thousandths, not %d" % [
				strike,
				factor,
				TYPE_FACTORS[strike],
			]
	# A strike is strong or weak against each of the struck species' types (#701): the Lesser
	# Growth strike on shadow and might, strong and then weak.
	var mixed: Array[bool] = [true, false]
	if chart.strong_types("growth", "mixed") != mixed:
		return "a growth strike on shadow and might isn't strong and then weak"
	var result: String = _typed_strikes(true)
	result = result if not result.is_empty() else _typed_strikes(false)
	return result if not result.is_empty() else _check_least_damage()


## A strike that lands deals at least 1 (#702): a strike of 1 at ×0.5 still deals 1.
func _check_least_damage() -> String:
	var auto_types: Dictionary[String, String] = { WEAK: "mana" }
	var types: Dictionary[String, PackedStringArray] = { "greater": PackedStringArray(["arcane"]) }
	var chart: TypeEffectivenessFeature = TypeEffectivenessFeature.new(types, auto_types)
	if chart.factor("mana", "greater") != 500:
		return "a mana strike on the Greater arcane type isn't ×0.5"
	var state: GameState = _strike_state([Vector2i.ZERO], [chart])
	state.set_enabled(TypeEffectivenessFeature.ID, true)
	var damage: int = TypeEffectivenessFeature.scaled(state, 1, WEAK, false, "greater")
	return "" if damage == 1 else "a strike of 1 at ×0.5 dealt %d, not 1" % damage


## Why the weak species' strikes, with the type chart `on` or off, weren't for their damage after
## it, or "": a companion beside a wild monster, both of the weak species, strike each other once
## in a second, and then the player fires the special.
func _typed_strikes(on: bool) -> String:
	var state: GameState = _strike_state([Vector2i.ZERO], [_type_chart()])
	state.set_enabled(TypeEffectivenessFeature.ID, on)
	FlowSteps.carry(state, 0, [WEAK])
	var _player: Entity = state.add_entity(0, Vector2i(3, 0))
	var _joined: Array[WildMonsterStruck] = _wild_strikes_over(state, 1, Vector2i(-3, 0))
	var hit: int = Fixed.scale(WEAK_STRENGTH, 1500 if on else Fixed.ONE)
	var ticks: int = WildAttackFeature.STRIKE_TICKS
	var struck: Array[WildMonsterStruck] = _wild_strikes_over(state, ticks, Vector2i(1, 0))
	var monster: int = _wild(state).monsters[0]
	if (struck.size() != 1 or struck[0].damage != hit
			or _hp(state, monster) != OUTCOME_HP - hit):
		return "with the chart %s, the strikes weren't for %d" % [on, hit]
	# The wild monster's auto attack carries the chart's marks for its damage number (#764).
	var marks: Array[bool] = []
	if on:
		marks.append(true)
	if struck[0].strong != marks:
		return "with the chart %s, the wild monster's hit was strong %s" % [on, struck[0].strong]
	var special: int = Fixed.scale(WEAK_STRENGTH, SPECIAL_POWER)
	special = Fixed.scale(special, 2000 if on else Fixed.ONE)
	var felled: Array[SpecialStruck] = _specials_in(state, _fire())
	if felled.size() != 1 or felled[0].damage != special:
		return "with the chart %s, the special didn't strike for %d" % [on, special]
	return _special_marks(felled[0], on)


## Why the weak species' special `struck`, with the type chart `on` or off, didn't carry the
## chart's marks (#701), or "": with it on, strong against the wild monster's one type, shown as one
## mark after the damage and tinted as strong; with it off, none and untinted.
static func _special_marks(struck: SpecialStruck, on: bool) -> String:
	var strong: Array[bool] = []
	if on:
		strong.append(true)
	if struck.strong != strong:
		return "with the chart %s, the special's hit was strong %s, not %s" % [
			on,
			struck.strong,
			strong,
		]
	var label: Label3D = RisingText.make(Vector2i.ZERO, DamageNumbersView.text_of(struck))
	TypeMarks.add_to(label, struck.strong)
	var marks: int = label.get_child_count()
	var tint: Color = label.modulate
	label.free()
	if marks != strong.size() or tint != (TypeMarks.STRONG_TINT if on else Color.WHITE):
		return "with the chart %s, the special's damage showed %d marks tinted %s" % [
			on,
			marks,
			tint,
		]
	return ""


## The type chart's feature for the type checks: the weak species is Lesser Nature, its auto attack
## Lesser Titan and its special Greater Titan.
static func _type_chart() -> TypeEffectivenessFeature:
	var types: Dictionary[String, PackedStringArray] = {
		WEAK: PackedStringArray(["growth"]),
		"double": PackedStringArray(["growth", "breeze"]),
		"greater": PackedStringArray(["arcane"]),
		"mixed": PackedStringArray(["shadow", "might"]),
	}
	var auto_types: Dictionary[String, String] = { WEAK: "might" }
	var special_types: Dictionary[String, String] = { WEAK: "titan" }
	return TypeEffectivenessFeature.new(types, auto_types, special_types)


## A companion that faints is swapped for the next monster its player carries (#597): the faint
## chooses the first one carried that hasn't fainted, which joins the next tick, while a swap back
## to the fainted one does nothing. Once every one carried has fainted, none is chosen or joins.
func _check_relieved() -> String:
	var state: GameState = _strike_state([Vector2i.ZERO])
	FlowSteps.carry(state, 0, [WEAK, STRONG])
	var _player: Entity = state.add_entity(0, Vector2i(3, 0))
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	var chosen: Array[int] = _faint_companion(state)
	if chosen.size() != 1 or chosen[0] != 1:
		return "the fainted companion wasn't swapped for the next one carried: %s" % [chosen]
	if _swaps_in(state, 1) != 0:
		return "a swap picked the carried monster that fainted"
	if companions.species_of(companions.companion_of(0)) != STRONG:
		return "the next one carried didn't join its player the tick after the faint"
	chosen = _faint_companion(state)
	Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	if not chosen.is_empty() or companions.companion_of(0) != 0:
		return "a companion was chosen or joined with every monster carried fainted"
	return ""


## Steps `state` with the companion of slot 0 kept beside the wild monster in the middle until it
## faints; returns the places chosen in its place.
func _faint_companion(state: GameState) -> Array[int]:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	var chosen: Array[int] = [-1]
	var companion: Entity = state.entity(companions.companion_of(0))
	for _tick: int in WildAttackFeature.STRIKE_TICKS * 110:
		if companion == null or state.entity(companion.id) == null:
			break
		chosen.clear()
		companion.tile = Vector2i(-1, 0)
		Simulation.step(state, still)
		for event: RefCounted in state.events:
			var swap: CompanionChosen = event as CompanionChosen
			if swap != null:
				chosen.append(swap.place)
	return chosen


## Steps `state` once with player 0 standing and swapping to `swap`; returns how many swaps it
## raised.
func _swaps_in(state: GameState, swap: int) -> int:
	var command: Command = Command.new()
	command.swap = swap
	var commands: Array[Command] = [command]
	Simulation.step(state, commands)
	var raised: int = 0
	for event: RefCounted in state.events:
		raised += 1 if event is CompanionChosen else 0
	return raised


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
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
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
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var before: int = health.hp_of(state, target_id)
	var strikes: Array[WildMonsterStruck] = _wild_strikes_over(state, ticks, companion_tile)
	if strikes.size() != 1 or strikes[0].target_id != target_id:
		return "the wild monster didn't strike %s once in a second" % what
	# The hit comes off their HP (#455).
	if health.hp_of(state, target_id) != maxi(before - strikes[0].damage, 0):
		return "the wild monster's hit didn't take %s's HP down by its damage" % what
	return ""


## Hit on `companion_tile` until their HP is gone, the companion falls once (#455) and goes back to
## its player (#456): EntityFell and CompanionReturned are raised on the hit that takes the last of
## it, the companion leaves the instance, and it doesn't join its player again here.
func _check_companion_falls(
	state: GameState,
	companion_tile: Vector2i,
	companion_id: int,
) -> String:
	var falls: int = 0
	var returns: int = 0
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	for _tick: int in WildAttackFeature.STRIKE_TICKS * 110:
		var companion: Entity = state.entity(companions.companion_of(0))
		if companion != null:
			companion.tile = companion_tile
		Simulation.step(state, still)
		for event: RefCounted in state.events:
			var fell: EntityFell = event as EntityFell
			falls += 1 if fell != null and fell.entity_id == companion_id else 0
			var returned: CompanionReturned = event as CompanionReturned
			returns += 1 if returned != null and returned.companion_id == companion_id else 0
	if falls != 1 or returns != 1 or state.entity(companion_id) != null:
		return "the companion fell %d times and went back %d times, not once each" % [
			falls,
			returns,
		]
	if companions.companion_of(0) != 0:
		return "the companion that went back to its player joined them again in the same instance"
	return ""


## The wild monsters' strikes over `ticks` ticks of the player standing still, with the player's
## companion put on `companion_tile` before each.
func _wild_strikes_over(
		state: GameState,
		ticks: int,
		companion_tile: Vector2i,
) -> Array[WildMonsterStruck]:
	var still: Array[Command] = FlowSteps.command(Command.NO_MOVE)
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
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
## specials, and the wild monsters' attacks, with the `extra` features (a type chart) before the
## companions' attacks, which read them (#822). A species has one HP (#835), a companion's here: the
## wild monsters are worn down to OUTCOME_HP first, so their companion outlasts them.
func _strike_state(spots: Array[Vector2i], extra: Array[Feature] = []) -> GameState:
	var region: Region = _outcome_state(WEAK, spots).region
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new({ WEAK: COMPANION_HP }),
		WildMonsterFeature.new([], [], { WEAK: WEAK_STRENGTH }),
		DominationFeature.new(),
		WildAttackFeature.new(),
		HidingFeature.new(),
		CompanionFeature.new(),
		CompanionSwapFeature.new(),
	]
	ordered.append_array(extra)
	ordered.append_array([
		CompanionAttackFeature.new(),
		SpecialAttackFeature.new({ WEAK: SPECIAL_POWER }, { WEAK: SPECIAL_TICKS }),
		HarvestFeature.new({ WEAK: _hide_table() }),
	])
	var state: GameState = GameState.new(region, 1, ordered)
	for monster: int in _wild(state).monsters:
		_wild(state).wound(state, monster, COMPANION_HP - OUTCOME_HP)
	return state


## The weak species' harvest table in the strike checks: it always rolls HIDE_LOOT.
static func _hide_table() -> LootTable:
	var table: LootTable = LootTable.new()
	table.id = WEAK
	table.kind = LootTable.HARVEST
	for item: String in HIDE_LOOT:
		table.items.append(item)
		table.chances.append(Fixed.ONE)
		table.mins.append(HIDE_LOOT[item])
		table.maxes.append(HIDE_LOOT[item])
	return table


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
## blink out: it shrinks away calmly, and then it's gone, and so is the brace. Before the totem,
## a spikes hit flashes thorns on the wall segment the monster pushes on, which then go (#777).
func _check_view(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree)
	var driver: GameDriver = FlowGame.held_driver(main)
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	FlowSteps.drop_beach_toad(driver.state)
	# Drawn now, not left to whether a frame has passed yet.
	view.show_state()
	if view.figures.size() != 1:
		main.queue_free()
		return "the main scene doesn't show the wild monster's figure"
	var figure: HexPiece = view.figures.values()[0]
	var _walked: Array[RefCounted] = FlowSteps.walk(driver.state, FlowSteps.BASIC_RING)
	var result: String = _check_spikes_hit(main, driver)
	if result.is_empty():
		result = _check_totem_button(main)
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
	var hits: SpikesHitView = main.get_node("Instance/SpikesHitView") as SpikesHitView
	if result.is_empty() and (is_instance_valid(figure) or not hits.flashes.is_empty()):
		result = "the dominated figure or the spikes' thorns were still there after going"
	main.queue_free()
	await tree.process_frame
	return result


## The ring around the wild monster waits for a totem: a spikes hit on it flashes thorns, a shape,
## on the wall segment nearest to it, the one it strikes (#777).
func _check_spikes_hit(main: Node, driver: GameDriver) -> String:
	var hits: SpikesHitView = main.get_node("Instance/SpikesHitView") as SpikesHitView
	var player: Entity = driver.state.player(0)
	var monster: Entity = driver.state.entity(_wild(driver.state).monsters[0])
	var walls: Array[Vector2i] = _domination(driver.state).ring_waiting(driver.state, player.id)
	var wall: Vector2i = walls[RingShape.nearest(walls, monster.tile)]
	var struck: Array[RefCounted] = [SpikesStruck.new(monster.id, player.id, SPIKES_DAMAGE)]
	FlowSteps.raise(driver, struck)
	if hits.flashes.size() != 1 or hits.flashes[0].tile != wall:
		return "a spikes hit flashed %d times, not once on the wall segment %s" % [
			hits.flashes.size(),
			wall,
		]
	var thorn: MeshInstance3D = hits.flashes[0].get_child(0).get_child(0) as MeshInstance3D
	var cone: CylinderMesh = thorn.mesh as CylinderMesh if thorn != null else null
	if cone == null or cone.top_radius != 0.0:
		return "the spikes' flash shows no thorns"
	return ""


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
	if not _presses_alone(totem, stick):
		return "a touch on the totem's button didn't press place_totem alone, or didn't let go"
	totem.touch = false
	return _check_special_button(main)


## The special attack's button (#431) shows on a touch screen, with no cooldown while the special is
## ready, and a touch on it presses special_attack alone.
func _check_special_button(main: Node) -> String:
	var special: SpecialButton = main.get_node("Hud/SpecialButton") as SpecialButton
	var stick: TouchStick = main.get_node("Hud/TouchStick") as TouchStick
	special.touch = true
	special.lay_out_in(special.get_viewport_rect().size)
	var ready: bool = special.corner_text().is_empty() and special.cooldown_share() == 0.0
	if not special.visible or not ready:
		return "the special's button doesn't show, ready, on a touch screen"
	# No companion here, so nothing to strike with: shown, but faded.
	if special.usable():
		return "the special's button shows usable with no companion to strike with"
	if special.rect().intersects(
		(main.get_node("Hud/TotemButton") as TotemButton).rect()
	):
		return "the special's button covers the totem's"
	if not _presses_alone(special, stick):
		return "a touch on the special's button didn't press special_attack alone, or didn't let go"
	special.touch = false
	return ""


## Whether a touch on `button` presses its action and doesn't start `stick`, and lifting it lets go.
func _presses_alone(button: ActionButton, stick: TouchStick) -> bool:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = button.rect().get_center()
	touch.pressed = true
	button.get_viewport().push_input(touch)
	var pressed: bool = Input.is_action_pressed(button.action)
	var stick_held: bool = stick.is_held()
	var lift: InputEventScreenTouch = touch.duplicate() as InputEventScreenTouch
	lift.pressed = false
	button.get_viewport().push_input(lift)
	return pressed and not stick_held and not Input.is_action_pressed(button.action)


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
	var fill: SealFillView = main.get_node("SealFillView") as SealFillView
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	var seal: RingSeal = _domination(state).seals.get(state.player(0).id)
	for _tick: int in Fixed.div_floor(seal.seal_ticks, 2):
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
	fill.show_state()
	var sealed: int = 0
	for tile: Vector2i in seal.walls:
		if grid.tile_color_of(tile) == fill.seal_color:
			sealed += 1
	if (sealed != SealFillView.sealed_tiles(seal).size()
			or sealed == 0
			or sealed == seal.walls.size()):
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
	for monster: DominatedMonster in ProfileStore.load_from(SAVE_PATH).dominated_monsters:
		species.append(monster.species)
	var expected: String = _dominated_species(events)
	var saved_one: bool = species.size() == 1 and species[0] == expected
	if result.is_empty() and (expected.is_empty() or not saved_one):
		result = "the dominated %s wasn't saved into the profile: %s" % [expected, species]
	if result.is_empty():
		result = _check_harvest_taken(main)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## A wild monster felled in sight (#629): this machine's player's own materials burst from where it
## lies and land in their profile; a drop with only another player's roll shows and gives nothing.
func _check_harvest_taken(main: Node) -> String:
	var driver: GameDriver = FlowGame.held_driver(main)
	var holder: ProfileHolder = FlowGame.holder(main)
	var view: HarvestView = main.get_node("Instance/HarvestView") as HarvestView
	var monster: Entity = driver.state.entity(_wild(driver.state).monsters[0])
	monster.tile = FlowSteps.sight_of(driver.state)[0]
	var wild: WildMonsterFeature = _wild(driver.state)
	wild.wound(driver.state, monster.id, _hp(driver.state, monster.id), true)
	# Earlier rolls in this session may have given moss already (a blank's instance table, #943):
	# only what this drop adds counts.
	var had: Dictionary[String, int] = holder.keeper.profile.materials.duplicate()
	var others: Dictionary[int, Dictionary] = { 1: HIDE_LOOT }
	var dropped: Array[RefCounted] = [Harvested.new(monster.id, WEAK, monster.tile, others)]
	FlowSteps.raise(driver, dropped)
	if not view.bursts.is_empty():
		return "another player's materials burst for this one"
	var mine: Dictionary[int, Dictionary] = { 0: HIDE_LOOT, 1: { "moss": 1 } }
	dropped = [Harvested.new(monster.id, WEAK, monster.tile, mine)]
	FlowSteps.raise(driver, dropped)
	(main.get_node("EventBus") as EventBus).flush()
	var gained: int = holder.keeper.profile.materials.get("hide", 0) - had.get("hide", 0)
	if view.bursts.size() != 1 or view.bursts[0].text != ChestView.loot_text(HIDE_LOOT):
		return "the felled wild monster's materials didn't burst into this player's own"
	if gained != HIDE_LOOT["hide"] or holder.keeper.profile.materials.get("moss", 0) != had.get(
		"moss",
		0,
	):
		return "the profile took %d hide from the felled wild monster, not this player's %s" % [
			gained,
			HIDE_LOOT,
		]
	return ""


## The species of the first wild monster dominated in `events`, or "".
func _dominated_species(events: Array[RefCounted]) -> String:
	var dominated: Array[WildMonsterDominated] = _dominated(events)
	return dominated[0].species if not dominated.is_empty() else ""


## Species (#133): a spot its region piece names always has that species (the arena's boss is a
## Tikazzir); the others roll from their blueprint's list, the same way for the same seed, every
## species on the list turning up over enough seeds, and the domination carries it. Every wild
## monster gets a short id (#700), the same for the same seed and apart from the others', and the
## domination carries it too.
func _check_species() -> String:
	var rolled: Dictionary[String, bool] = {}
	for seed_value: int in 24:
		var arena: GameState = InstanceBlueprints.create(FlowSteps.ARENA, seed_value)
		if _wild(arena).species_of(_wild(arena).monsters[0]) != "tikazzir":
			return "seed %d's arena boss isn't the Tikazzir it names" % seed_value
		var basic: String = _first_species(FlowSteps.basic(seed_value))
		if basic != _first_species(FlowSteps.basic(seed_value)):
			return "seed %d placed two different species" % seed_value
		rolled[basic] = true
	var listed: Array = InstanceBlueprints.blueprint(FlowSteps.BASIC).wild_species.keys()
	if rolled.size() != listed.size():
		return "the basic instance's spots rolled %s, not every one of %s" % [rolled.keys(), listed]
	var dominated: String = _check_short_ids()
	if not dominated.is_empty():
		return dominated
	var wounded: String = _check_wounded()
	return wounded if not wounded.is_empty() else _check_relieved()


## Every wild monster gets a short id (#700), the same for the same seed and apart from the others',
## and the domination carries it, with its species.
func _check_short_ids() -> String:
	var state: GameState = FlowSteps.basic(1)
	var short_ids: Dictionary[String, bool] = {}
	for monster: int in _wild(state).monsters:
		short_ids[_wild(state).short_id_of(monster)] = true
	var first: String = _wild(state).short_id_of(_wild(state).monsters[0])
	var again: GameState = FlowSteps.basic(1)
	var same: bool = _wild(again).short_id_of(_wild(again).monsters[0]) == first
	if not ShortId.is_valid(first) or short_ids.size() != _wild(state).monsters.size() or not same:
		return "the wild monsters' short ids aren't valid, apart, and the same for the same seed"
	var events: Array[RefCounted] = FlowSteps.walk(state, FlowSteps.BASIC_RING)
	events.append_array(_settle(state))
	if _dominated_species(events) != _first_species(FlowSteps.basic(1)):
		return "the domination didn't carry the dominated monster's species"
	if _dominated(events)[0].short_id != first:
		return "the domination didn't carry the dominated monster's short id"
	return ""


## A legend can mark a wild monster wounded (#389): it starts at WOUNDED_HP of its full HP, never
## below 1, while the one beside it starts at full.
func _check_wounded() -> String:
	var tiles: String = "# W\n\n## Tiles\n\n```\n🤕🔴🐸\n```\n\n## Legend\n\n"
	tiles += "- `🤕`: a wild monster, always ombulumo, wounded\n"
	tiles += "- `🐸`: a wild monster, always ombulumo\n"
	tiles += "- `🔴`: where player 1 starts\n"
	var region: Region = InstanceBlueprints.read_region(tiles)
	var marked: int = 0
	for meaning: String in region.placed(WildSpotPlacements.KIND).values():
		marked += 1 if WildSpot.read(meaning).wounded else 0
	if not region.problem.is_empty() or marked != 1:
		return "a legend didn't mark its wild monster wounded: " + region.problem
	var hp: Dictionary[String, int] = { "ombulumo": OUTCOME_HP }
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(hp),
		WildMonsterFeature.new([], [], { "ombulumo": WEAK_STRENGTH }),
	]
	var state: GameState = GameState.new(region, 1, ordered)
	var wild: WildMonsterFeature = _wild(state)
	var weak: int = maxi(Fixed.scale(OUTCOME_HP, WildMonsterFeature.WOUNDED_HP), 1)
	var expected: Array[int] = [weak, OUTCOME_HP]
	var started: Array[int] = []
	for monster: int in wild.monsters:
		started.append(_hp(state, monster))
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
	return state.feature(WildMonsterFeature.ID) as WildMonsterFeature


func _health(state: GameState) -> HealthFeature:
	return state.feature(HealthFeature.ID) as HealthFeature


## The HP `entity_id` has left in `state` (HealthFeature's, wild monsters' too since #835).
func _hp(state: GameState, entity_id: int) -> int:
	return _health(state).hp_of(state, entity_id)


func _trails(state: GameState) -> TrailFeature:
	return state.feature(TrailFeature.ID) as TrailFeature


func _domination(state: GameState) -> DominationFeature:
	return state.feature(DominationFeature.ID) as DominationFeature
