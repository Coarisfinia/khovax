class_name SurveyLayer
extends Control
## A layer over the SurveyView it's a child of, like its held marks (#637) and the followed quest
## game/ hands it (#1298, #1666): it covers the Survey, lets every touch through, and works out what
## it shows after the
## Survey each frame while it shows, then draws it.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	# After the Survey, its parent, which processes first.
	if is_visible_in_tree():
		show_state()
		queue_redraw()


## Works out what it shows from the Survey. Called every frame while it shows; tests call it
## directly, after the Survey's own.
func show_state() -> void:
	return


## Where the pointer rests on the Survey, in its own pixels, as SurveyQuestPicker sees it; not
## finite while it's elsewhere. A layer that shows what's under it keeps it.
func point(_at: Vector2) -> void:
	return


## Whether it draws the arrow `key` of SurveyView.quest_targets itself, so the Survey leaves it out
## (#1298).
func draws_arrow(_key: String) -> bool:
	return false
