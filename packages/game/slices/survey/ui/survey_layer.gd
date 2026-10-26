class_name SurveyLayer
extends Control
## A layer over the SurveyView it's a child of, like its held marks (#637) and its followed quest
## (#1298): it covers the Survey, lets every touch through, and works out what it shows after the
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
