class_name Daylight
extends Node
## The day and night look (#1247): the sun's light and the ambient light of the instance this
## machine's player is in, by the hour of the world's one clock (DayClock), which every realm
## shares.
## Only the look is the realm's own, from its file (Realm.day_light and the rest): a realm whose
## day and night look alike hides the hour, though its monsters still keep it. Dawn and dusk blend
## over TWILIGHT_HOURS: the hour before dawn brightens into day, the hour after dusk darkens into
## night. The fog's cloud, drawn unshaded, is tinted by the sun's and the ambient light together
## (#1360), so it dims with the night too. Presentation only: it reads the state and never writes
## it.

## How many hours dawn and dusk take to blend one look into the other.
const TWILIGHT_HOURS: float = 1.0
## The look of an instance no realm draws (the playground): always lit, as before #1247.
const UNREALMED_LIGHT: Color = Color.WHITE
const UNREALMED_AMBIENCE: Color = Color.BLACK

@export var driver: Session
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var cloud: FogCloud


func _process(_delta: float) -> void:
	var state: GameState = driver.state
	if state == null:
		return
	var realm: Realm = Realms.holding(driver.local_instance_name())
	var ticks: float = state.world_tick + driver.tick_fraction()
	sun.light_color = light_of(realm, ticks)
	world_environment.environment.ambient_light_color = ambience_of(realm, ticks)
	cloud.light_by(cloud_light(sun.light_color, world_environment.environment.ambient_light_color))


## The light the unshaded cloud is seen in under the sun's `light` and the `ambience`: both
## together, as a lit surface facing the sun gets, at most white.
static func cloud_light(light: Color, ambience: Color) -> Color:
	var sum: Color = light + ambience
	return Color(minf(sum.r, 1.0), minf(sum.g, 1.0), minf(sum.b, 1.0))


## The sun's light in `realm` (null for none) at the world's tick `ticks`.
static func light_of(realm: Realm, ticks: float) -> Color:
	if realm == null:
		return UNREALMED_LIGHT
	return _blend(realm.night_light, realm.day_light, ticks)


## The ambient light in `realm` (null for none) at the world's tick `ticks`.
static func ambience_of(realm: Realm, ticks: float) -> Color:
	if realm == null:
		return UNREALMED_AMBIENCE
	return _blend(realm.night_ambience, realm.day_ambience, ticks)


## How much of the day's look shows at the world's tick `ticks`: 1 by day, 0 at night, easing
## between them at dawn and dusk.
static func day_share(ticks: float) -> float:
	var hour: float = fposmod(DayClock.DAWN + ticks / DayClock.TICKS_PER_HOUR, DayClock.HOURS)
	var rising: float = (hour - DayClock.DAWN) / TWILIGHT_HOURS + 1.0
	var setting: float = (DayClock.DUSK - hour) / TWILIGHT_HOURS + 1.0
	return smoothstep(0.0, 1.0, minf(rising, setting))


## The whole 0xRRGGBB colours `night` and `day` blended by the day's share at `ticks`.
static func _blend(night: int, day: int, ticks: float) -> Color:
	return TileLooks.rgb(night).lerp(TileLooks.rgb(day), day_share(ticks))
