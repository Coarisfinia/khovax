class_name InputGlyphs
extends RefCounted
## The glyph of the key, button or axis that presses an InputMap action on a device (#583): a
## white shape, drawn in ink like the UI's icons. It reads the action's own events, so a hint always
## shows what the InputMap says. Only the glyphs a hint shows are in the game: a key or button
## without one, and touch, whose hints are the buttons tapped, show none.

const KEYS: Dictionary[Key, Texture2D] = {
	KEY_ENTER: preload("res://assets/kenney-input-prompts/keyboard_enter.svg"),
	KEY_ESCAPE: preload("res://assets/kenney-input-prompts/keyboard_escape.svg"),
	KEY_E: preload("res://assets/kenney-input-prompts/keyboard_e.svg"),
	KEY_T: preload("res://assets/kenney-input-prompts/keyboard_t.svg"),
	KEY_V: preload("res://assets/kenney-input-prompts/keyboard_v.svg"),
	KEY_X: preload("res://assets/kenney-input-prompts/keyboard_x.svg"),
}
const BUTTONS: Dictionary[JoyButton, Texture2D] = {
	JOY_BUTTON_A: preload("res://assets/kenney-input-prompts/controller_button_a.svg"),
	JOY_BUTTON_B: preload("res://assets/kenney-input-prompts/controller_button_b.svg"),
	JOY_BUTTON_X: preload("res://assets/kenney-input-prompts/controller_button_x.svg"),
	JOY_BUTTON_Y: preload("res://assets/kenney-input-prompts/controller_button_y.svg"),
	JOY_BUTTON_DPAD_DOWN: preload("res://assets/kenney-input-prompts/controller_dpad_down.svg"),
}
## A trigger or stick, by its axis.
const AXES: Dictionary[JoyAxis, Texture2D] = {
	JOY_AXIS_TRIGGER_RIGHT:
	preload("res://assets/kenney-input-prompts/controller_trigger_right.svg"),
}


## The glyph of the first key, button or axis that presses `action` on `device`, or null for none.
static func of(action: StringName, device: DeviceInUse.Device) -> Texture2D:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		var glyph: Texture2D = _glyph(event, device)
		if glyph != null:
			return glyph
	return null


## The glyph of `event` on `device`, or null when it's another device's or has none.
static func _glyph(event: InputEvent, device: DeviceInUse.Device) -> Texture2D:
	var key: InputEventKey = event as InputEventKey
	if key != null and device == DeviceInUse.Device.KEYBOARD:
		# An action names a key by where it lies (WASD) or by what it says (Enter).
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return KEYS.get(code)
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null and device == DeviceInUse.Device.CONTROLLER:
		return BUTTONS.get(button.button_index)
	var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if motion != null and device == DeviceInUse.Device.CONTROLLER:
		return AXES.get(motion.axis)
	return null
