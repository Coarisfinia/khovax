class_name DamageNumbersView
extends Node3D
## The damage numbers (#431, #764): a strike's damage rises from what it struck and fades, with the
## type chart's marks after it (TypeMarks, #701). A companion's special shows it largest, and says
## in words when the wild monster fainted, never by color alone (#68); auto attacks, a companion's
## and a wild monster's on a companion or a player, show it smaller and quicker, so their frequent
## hits stay calm. A wild monster's hit on the trail isn't damage to anyone, so it shows none. The
## player's DamageNumbersChoice turns them off, the fainting's words staying, and sizes them.
## Calm, as the camera is: no shake and no flash. It only reads the tick's events and the state.

const SECONDS: float = 1.2
const RISE: float = 0.6
const FAINTED_TEXT: String = "fainted"
## An auto attack's number: its seconds, its rise and its size as a share of a special's.
const AUTO_SECONDS: float = 0.7
const AUTO_RISE: float = 0.35
const AUTO_SHARE: float = 0.7
## How far toward the camera an auto attack's number starts, in world units: the camera looks down
## from that side and never turns (FollowCamera), so it shows below a special's on the same monster
## rather than over it.
const AUTO_BELOW: float = 0.45

@export var driver: Session
## Whose Settings say whether the numbers show and how large (DamageNumbersChoice).
@export var graphics: Graphics

## Whether the numbers show and how large, made from `graphics` once it's ready.
var choice: DamageNumbersChoice = DamageNumbersChoice.new(null)
## The damage still rising, newest last. Kept here so tests can read it.
var strikes: Array[Label3D] = []


func _ready() -> void:
	choice = DamageNumbersChoice.new(graphics)
	var _connected: int = driver.ticked.connect(_on_ticked)


## Shows the special `struck` landing on `tile`.
func show_strike(tile: Vector2i, struck: SpecialStruck) -> void:
	var text: String = text_of(struck, _shown())
	# With the numbers off, only the fainting's words show, without marks.
	var strong: Array[bool] = []
	if _shown():
		strong = struck.strong
	if not text.is_empty():
		_rise(tile, text, strong, false)


## Shows an auto attack's `damage` landing on `tile`, `strong` as the type chart had it.
func show_auto(tile: Vector2i, damage: int, strong: Array[bool]) -> void:
	if _shown():
		_rise(tile, "-%d" % damage, strong, true)


## What `struck` shows: its damage while `numbers` show, and on a line after it that the wild
## monster fainted. A bind taking hold (#1167) deals nothing, and shows nothing.
static func text_of(struck: SpecialStruck, numbers: bool = true) -> String:
	var text: String = "-%d" % struck.damage if numbers and struck.damage > 0 else ""
	if struck.felled:
		text += ("\n" if not text.is_empty() else "") + FAINTED_TEXT
	return text


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for event: RefCounted in driver.local_events(events):
		if event is SpecialStruck:
			var special: SpecialStruck = event as SpecialStruck
			var monster: Entity = driver.state.entity(special.monster_id)
			if monster != null:
				show_strike(monster.tile, special)
		elif event is CompanionStruck:
			var auto: CompanionStruck = event as CompanionStruck
			var struck: Entity = driver.state.entity(auto.monster_id)
			if struck != null:
				show_auto(struck.tile, auto.damage, auto.strong)
		elif event is WildMonsterStruck:
			var wild: WildMonsterStruck = event as WildMonsterStruck
			if wild.target_id != 0:
				show_auto(wild.tile, wild.damage, wild.strong)


## Lets `text` rise from `tile` with `strong`'s marks, an `auto` attack's smaller and quicker, at
## the player's size.
func _rise(tile: Vector2i, text: String, strong: Array[bool], auto: bool) -> void:
	var label: Label3D = RisingText.make(tile, text)
	# The marks are sized from the label's pixels, so it's sized first.
	label.pixel_size *= (AUTO_SHARE if auto else 1.0) * choice.size_share()
	TypeMarks.add_to(label, strong)
	add_child(label)
	strikes.append(label)
	if auto:
		label.position.z += AUTO_BELOW
		RisingText.rise(label, AUTO_SECONDS, AUTO_RISE, _drop)
	else:
		RisingText.rise(label, SECONDS, RISE, _drop)


func _shown() -> bool:
	return choice.shown()


func _drop(label: Label3D) -> void:
	strikes.erase(label)
	label.queue_free()
