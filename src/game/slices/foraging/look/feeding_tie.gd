class_name FeedingTie
extends Node
## Ties the wild monsters' figures to their feeding (#1203): every frame it tells the wild
## monsters' view which of them feed now, at their grass or water (ForagingFeature.is_feeding),
## and the view plays their Feed clip. The view sits in an earlier slice than the foraging rules,
## so it can't ask them itself. It only reads the state.

@export var driver: Session
## The view whose figures feed.
@export var wild_monsters: WildMonsterView


func _ready() -> void:
	# Before the view's own frame, so it picks its clips from this frame's feeding, never the last.
	process_priority = wild_monsters.process_priority - 1


func _process(_delta: float) -> void:
	show_state()


## Hands the view every wild monster feeding now. Called every frame; tests call it after stepping.
func show_state() -> void:
	var feeding: Dictionary[int, bool] = {}
	if driver != null and driver.state != null:
		for entity_id: int in wild_monsters.figures:
			if ForagingFeature.is_feeding(driver.state, entity_id):
				feeding[entity_id] = true
	wild_monsters.feeding = feeding
