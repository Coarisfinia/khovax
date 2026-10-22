class_name FlowInput
extends RefCounted
## Presses a controller's buttons, clicks and taps inside a flow, as the player's devices would
## (AGENTS.md: shared, never copied). Not a flow itself: the runner runs only the `test_*.gd` files.


## Presses the controller's `button` and lets go at once, into the viewport of `node`.
static func press_pad(node: Node, button: JoyButton) -> void:
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = button
	pad.pressed = true
	node.get_viewport().push_input(pad)
	var lift: InputEventJoypadButton = pad.duplicate() as InputEventJoypadButton
	lift.pressed = false
	node.get_viewport().push_input(lift)


## Presses the left button at `at` and lets go at once, from `device`: the mouse, or a touch as
## Godot emulates a mouse from it, into the viewport of `node`.
static func tap(node: Node, at: Vector2, device: int) -> void:
	var press: InputEventMouseButton = left_button(at, device)
	node.get_viewport().push_input(press)
	var lift: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	lift.pressed = false
	node.get_viewport().push_input(lift)


## The left button pressed at `at`, from `device`.
static func left_button(at: Vector2, device: int) -> InputEventMouseButton:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.device = device
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = at
	press.pressed = true
	return press
