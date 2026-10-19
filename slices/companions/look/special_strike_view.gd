class_name SpecialStrikeView
extends Node3D
## A companion's special attack landing (#431): the damage rises from the struck wild monster and
## fades, with the type chart's marks after it (TypeMarks, #701), and says so in words when it
## fainted, never by color alone (#68). Calm, as the camera is:
## no shake and no flash. It only reads the tick's events and the state.

const SECONDS: float = 1.2
const RISE: float = 0.6
const FAINTED_TEXT: String = "fainted"

@export var driver: Session

## The damage still rising, newest last. Kept here so tests can read it.
var strikes: Array[Label3D] = []


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


## Shows the special `struck` landing on `tile`.
func show_strike(tile: Vector2i, struck: SpecialStruck) -> void:
	var label: Label3D = RisingText.make(tile, text_of(struck))
	TypeMarks.add_to(label, struck.strong)
	add_child(label)
	strikes.append(label)
	RisingText.rise(label, SECONDS, RISE, _drop)


## What `struck` shows: its damage, and on a second line that the wild monster fainted.
static func text_of(struck: SpecialStruck) -> String:
	var text: String = "-%d" % struck.damage
	if struck.felled:
		text += "\n" + FAINTED_TEXT
	return text


## Only for a wild monster in the instance shown: the driver also passes on the events of one the
## player just left.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for event: RefCounted in events:
		var struck: SpecialStruck = event as SpecialStruck
		var monster: Entity = driver.state.entity(struck.monster_id) if struck != null else null
		if monster != null:
			show_strike(monster.tile, struck)


func _drop(label: Label3D) -> void:
	strikes.erase(label)
	label.queue_free()
