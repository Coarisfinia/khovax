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


## What `shown` returns (the glyphs a hint shows) after a key, a controller's button and a touch,
## each making its device the one in use (DeviceInUse, #1192), in that order; the device in use
## before is kept.
static func glyphs_by_device(shown: Callable) -> Array:
	var kept: DeviceInUse.Device = DeviceInUse.device
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SHIFT
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_MISC1
	var after: Array = []
	for used: InputEvent in [key, pad, InputEventScreenTouch.new()]:
		DeviceInUse.heard(used)
		after.append(shown.call())
	DeviceInUse.device = kept
	return after


## `wanted` with every glyph id in it (InputGlyphs) turned into its texture (ResourcePacks), in
## lists inside lists too, to compare with the glyphs a hint shows.
static func textures(wanted: Array) -> Array:
	var turned: Array = []
	for entry: Variant in wanted:
		if entry is String:
			var glyph: String = entry
			turned.append(ResourcePacks.texture(glyph))
		elif entry is Array:
			var inner: Array = entry
			turned.append(textures(inner))
		else:
			turned.append(entry)
	return turned


## The glyph badge on `button` (ActionGlyph), or null.
static func badge_of(button: Button) -> ActionGlyph:
	for child: Node in button.get_children():
		if child is ActionGlyph:
			return child as ActionGlyph
	return null


## The glyphs the badges on `buttons` show now, each following the device in use first.
static func badges_shown(buttons: Array[Button]) -> Array:
	var glyphs: Array = []
	for button: Button in buttons:
		var badge: ActionGlyph = badge_of(button)
		badge.follow()
		glyphs.append(badge.texture)
	return glyphs
