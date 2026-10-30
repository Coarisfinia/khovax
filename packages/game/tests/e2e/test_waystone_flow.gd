extends RefCounted
## Waystone flow (#1854, #1890): Morwe Wudhen has a waystone, a tile nobody walks, drawn as the
## standing stone. A player who comes next to it activates it once: it becomes their respawn point
## and joins the waystones they activated; a knocked-down player activates nothing, and the
## playground, without one, has no waystones. A player who falls in another instance with nobody to
## revive them comes back beside their respawn point, at full HP; once its tile no longer holds a
## waystone, or its instance is gone, they go to the world's spawn as before. The look lights the
## stone's hole and puts it out again, and the notice has its words. Fainted beasts come back at a
## waystone only while the host has them revived on waystones (#1891), which the notice says too.

const SEED: int = 7
## The forest's edge, north of Lumwen Hoal, with a waystone west of the way in.
const EDGE: String = "morwe_wudhen"
## How long the playground's wild monster takes at most to bring a player standing beside it down.
const FALL_TICKS: int = WildAttackFeature.STRIKE_TICKS * 60


func run(_tree: SceneTree) -> String:
	var result: String = _check_content()
	if result.is_empty():
		result = _check_activated()
	if result.is_empty():
		result = _check_respawned()
	if result.is_empty():
		result = _check_gone()
	if result.is_empty():
		result = _check_revived()
	if result.is_empty():
		result = _check_lit()
	return result


## The waystone is a kind nobody walks, drawn as the standing stone, which loads; Morwe Wudhen has
## one, which brings the waystones, and the playground has none.
func _check_content() -> String:
	if not TileKinds.has(WaystoneFeature.KIND) or TileKinds.is_walkable(WaystoneFeature.KIND):
		return "the waystone isn't a tile kind nobody walks"
	var look: TileBlueprint = TileLooks.of(WaystoneFeature.KIND)
	if look == null or ResourcePacks.model(look.model) == null:
		return "the waystone isn't drawn as a model that loads"
	if InstanceBlueprints.create(EDGE, SEED, 1).feature(WaystoneFeature.ID) == null:
		return "Morwe Wudhen's waystone brings no waystones"
	if FlowSteps.basic(SEED).feature(WaystoneFeature.ID) != null:
		return "the playground, without a waystone, has waystones"
	return ""


## A player put beside Morwe Wudhen's waystone activates it on the next tick: it's their respawn
## point and among the waystones they activated, and it's said once. Knocked down beside it, a
## player activates nothing.
func _check_activated() -> String:
	var downed: World = World.new(BlueprintSource.new(), SEED, EDGE)
	var down_edge: GameState = downed.instances[EDGE]
	var stone: Vector2i = _stone_of(down_edge)
	if stone == Vector2i.MAX:
		return "Morwe Wudhen has no waystone with ground beside it"
	downed.player(0).tile = _ground_beside(down_edge.region, stone)
	var knockdown: KnockdownFeature = down_edge.feature(KnockdownFeature.ID) as KnockdownFeature
	knockdown.knock_down(downed.player(0).id)
	downed.step(FlowSteps.command(Command.NO_MOVE))
	if not RespawnPoint.of(downed.stored(0, RespawnPoint.ENTRY)).is_empty():
		return "a knocked-down player activated a waystone"
	var world: World = World.new(BlueprintSource.new(), SEED, EDGE)
	var edge: GameState = world.instances[EDGE]
	world.player(0).tile = _ground_beside(edge.region, stone)
	world.step(FlowSteps.command(Command.NO_MOVE))
	var said: int = _activations(edge.events)
	if RespawnPoint.of(world.stored(0, RespawnPoint.ENTRY)) != [EDGE, stone]:
		return "a player beside the waystone didn't make it their respawn point"
	if WaystoneFeature.activated_in(edge, 0, EDGE) != [stone]:
		return "the waystone isn't among the ones the player activated"
	world.step(FlowSteps.command(Command.NO_MOVE))
	if said != 1 or _activations(edge.events) != 0:
		return "activating the waystone wasn't said once"
	return ""


## A player whose respawn point is Morwe Wudhen's waystone falls in the playground, beside its wild
## monster with nobody to revive them, and comes back beside the waystone, in Morwe Wudhen, at full
## HP.
func _check_respawned() -> String:
	var world: World = World.new(BlueprintSource.new(), SEED, FlowSteps.BASIC)
	var stone: Vector2i = _remember_stone(world, WaystoneFeature.KIND)
	var back: Entity = _fall(world)
	if back == null:
		return "the player never fell beside the wild monster"
	var edge: GameState = world.instances[EDGE]
	if world.instance_of(0) != EDGE or back.tile != _ground_beside(edge.region, stone):
		return "a fallen player didn't come back beside their waystone: %s" % back.tile
	var health: HealthFeature = edge.feature(HealthFeature.ID) as HealthFeature
	if health != null and health.hp_of(edge, back.id) != HealthFeature.PLAYER_HP:
		return "a player back at their waystone isn't at full HP"
	return ""


## A respawn point whose tile no longer holds a waystone, or whose instance doesn't exist, sends a
## fallen player to the world's spawn, as before.
func _check_gone() -> String:
	var world: World = World.new(BlueprintSource.new(), SEED, FlowSteps.BASIC)
	var start: Vector2i = world.instances[FlowSteps.BASIC].region.starts[0]
	var _stone: Vector2i = _remember_stone(world, Region.GROUND)
	var back: Entity = _fall(world)
	if back == null or world.instance_of(0) != world.start_name or back.tile != start:
		return "a player whose waystone is gone wasn't sent to the world's spawn"
	world = World.new(BlueprintSource.new(), SEED, FlowSteps.BASIC)
	world.set_entry(0, RespawnPoint.ENTRY, { "instance": "nowhere_at_all", "q": 0, "r": 0 })
	back = _fall(world)
	if back == null or world.instance_of(0) != world.start_name or back.tile != start:
		return "a player whose waystone's instance doesn't exist wasn't sent to the world's spawn"
	return ""


## A player beside Morwe Wudhen's waystone with a fainted beast keeps it fainted while the host
## hasn't turned revive on waystones on (the default); once it's on, the beast is back on the next
## tick, which WaystoneRevived says once.
func _check_revived() -> String:
	var world: World = World.new(BlueprintSource.new(), SEED, EDGE)
	var edge: GameState = world.instances[EDGE]
	FlowSteps.carry(edge, 0, ["ombulumo", "ombulumo"])
	var fainted: String = ShortId.stand_in(2)
	CompanionParty.faint(edge, 0, fainted)
	world.player(0).tile = _ground_beside(edge.region, _stone_of(edge))
	world.step(FlowSteps.command(Command.NO_MOVE))
	if not CompanionParty.has_fainted(edge, 0, fainted) or _count(edge.events, "revived") != 0:
		return "a fainted beast came back at a waystone with revive on waystones off"
	var turned_on: Dictionary = { HostSettings.REVIVE_ON_WAYSTONES: HostSettings.ON }
	world.set_entry(HostSettings.HOST, HostSettings.FEATURE_ID, turned_on)
	world.step(FlowSteps.command(Command.NO_MOVE))
	var said: int = _count(edge.events, "revived")
	if CompanionParty.has_fainted(edge, 0, fainted) or said != 1:
		return "a fainted beast didn't come back at a waystone with revive on waystones on"
	world.step(FlowSteps.command(Command.NO_MOVE))
	if _count(edge.events, "revived") != 0:
		return "beasts already back were revived again"
	var both: String = WaystoneNoticeTie.lines(true, true)
	if (not both.contains(WaystoneNoticeTie.line())
			or not both.contains(WaystoneNoticeTie.revived_line())):
		return "the notice doesn't say both when a waystone was activated and revived beasts"
	return ""


## The look lights the standing stone's hole, with a light in it, and puts it out again, back to
## the stone it showed; the notice says what an activated waystone does.
func _check_lit() -> String:
	var figure: Node3D = ResourcePacks.model("model_standing_stone").instantiate() as Node3D
	Toon.apply_to_model(figure)
	var glow: WaystoneGlow = WaystoneGlow.new()
	glow._ready()
	var hole: Array = _hole_of(figure)
	var result: String = ""
	if hole.is_empty():
		result = "the standing stone has no glowing part"
	else:
		var meshes: MeshInstance3D = hole[0]
		var surface: int = hole[1]
		var stone: Material = meshes.get_surface_override_material(surface)
		glow.light(figure, true)
		var lit: bool = meshes.get_surface_override_material(surface) != stone
		var lamp: bool = meshes.get_child_count() > 0
		glow.light(figure, false)
		if not lit or not lamp or WaystoneGlow.is_lit(figure):
			result = "an activated waystone's hole didn't light up with a light in it"
		elif meshes.get_surface_override_material(surface) != stone:
			result = "a waystone's hole put out didn't show its stone again"
	figure.free()
	glow.free()
	if (result.is_empty()
			and (WaystoneNoticeTie.title().is_empty() or WaystoneNoticeTie.line().is_empty())):
		result = "the waystone's notice has no words"
	return result


## The waystone of `state`'s region with ground beside it, or Vector2i.MAX.
static func _stone_of(state: GameState) -> Vector2i:
	for tile: Vector2i in state.region.sorted_tiles():
		var kind: String = state.region.terrain[tile]
		if kind == WaystoneFeature.KIND and _ground_beside(state.region, tile) != tile:
			return tile
	return Vector2i.MAX


## Makes Morwe Wudhen's waystone the respawn point of player 0 of `world`, as set on a tile of
## `kind`: a waystone, or ground for one whose tile changed since. Returns the waystone's tile.
static func _remember_stone(world: World, kind: String) -> Vector2i:
	var stone: Vector2i = _stone_of(world.instance(EDGE))
	var point: Dictionary = { "instance": EDGE, "q": stone.x, "r": stone.y, "kind": kind }
	world.set_entry(0, RespawnPoint.ENTRY, point)
	return stone


## Player 0 of `world`, put beside the playground's wild monster, awake, until they fall and come
## back as a new entity; null if they never fall.
static func _fall(world: World) -> Entity:
	var basic: GameState = world.instances[FlowSteps.BASIC]
	var wild: WildMonsterFeature = basic.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var first: Entity = world.player(0)
	first.tile = basic.entity(wild.monsters[0]).tile + Hex.DIRECTIONS[0]
	wild.sleep(wild.monsters[0], false)
	basic.set_enabled(SleepFeature.ID, false)
	for _tick: int in FALL_TICKS:
		world.step(FlowSteps.command(Command.NO_MOVE))
		if world.player(0) != null and world.player(0).id != first.id:
			return world.player(0)
	return null


## The first walkable tile next to `tile` in `region`, in direction order, or `tile`: where the
## world lands a player sent back to a waystone there.
static func _ground_beside(region: Region, tile: Vector2i) -> Vector2i:
	for direction: Vector2i in Hex.DIRECTIONS:
		if region.is_walkable(tile + direction):
			return tile + direction
	return tile


static func _activations(events: Array[RefCounted]) -> int:
	return _count(events, "activated")


## How many of `events` are WaystoneActivated ("activated") or WaystoneRevived ("revived").
static func _count(events: Array[RefCounted], what: String) -> int:
	var count: int = 0
	for event: RefCounted in events:
		var activated: bool = what == "activated" and event is WaystoneActivated
		if activated or (what == "revived" and event is WaystoneRevived):
			count += 1
	return count


## The standing stone's glowing part in `figure`: its mesh and surface, or empty.
static func _hole_of(figure: Node3D) -> Array:
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var meshes: MeshInstance3D = node as MeshInstance3D
		for surface: int in meshes.mesh.get_surface_count():
			var source: Material = meshes.mesh.surface_get_material(surface)
			if source != null and source.resource_name == WaystoneGlow.GLOW_PART:
				return [meshes, surface]
	return []
