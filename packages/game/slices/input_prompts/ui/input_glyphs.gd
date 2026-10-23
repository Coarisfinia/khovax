class_name InputGlyphs
extends RefCounted
## The glyph of the key, button or axis that presses an InputMap action on a device (#583): a
## white shape, drawn in ink like the UI's icons. It reads the action's own events, so a hint always
## shows what the InputMap says. Only the glyphs a hint shows are in the game: a key or button
## without one shows none, and so does touch, whose hints are the buttons tapped, but for the
## gestures that press an action too (GESTURES). Pointing at the screen, a click or a tap, has its
## own glyph (pointing).

const KEYS: Dictionary[Key, Texture2D] = {
	KEY_1: preload("res://assets/kenney-input-prompts/keyboard_1.svg"),
	KEY_2: preload("res://assets/kenney-input-prompts/keyboard_2.svg"),
	KEY_3: preload("res://assets/kenney-input-prompts/keyboard_3.svg"),
	KEY_EQUAL: preload("res://assets/kenney-input-prompts/keyboard_equals.svg"),
	KEY_MINUS: preload("res://assets/kenney-input-prompts/keyboard_minus.svg"),
	KEY_TAB: preload("res://assets/kenney-input-prompts/keyboard_tab.svg"),
	KEY_ENTER: preload("res://assets/kenney-input-prompts/keyboard_enter.svg"),
	KEY_ESCAPE: preload("res://assets/kenney-input-prompts/keyboard_escape.svg"),
	KEY_E: preload("res://assets/kenney-input-prompts/keyboard_e.svg"),
	KEY_Q: preload("res://assets/kenney-input-prompts/keyboard_q.svg"),
	KEY_R: preload("res://assets/kenney-input-prompts/keyboard_r.svg"),
	KEY_T: preload("res://assets/kenney-input-prompts/keyboard_t.svg"),
	KEY_V: preload("res://assets/kenney-input-prompts/keyboard_v.svg"),
	KEY_X: preload("res://assets/kenney-input-prompts/keyboard_x.svg"),
}
const BUTTONS: Dictionary[JoyButton, Texture2D] = {
	JOY_BUTTON_A: preload("res://assets/kenney-input-prompts/controller_button_a.svg"),
	JOY_BUTTON_B: preload("res://assets/kenney-input-prompts/controller_button_b.svg"),
	JOY_BUTTON_X: preload("res://assets/kenney-input-prompts/controller_button_x.svg"),
	JOY_BUTTON_Y: preload("res://assets/kenney-input-prompts/controller_button_y.svg"),
	JOY_BUTTON_BACK: preload("res://assets/kenney-input-prompts/controller_button_back.svg"),
	JOY_BUTTON_START: preload("res://assets/kenney-input-prompts/controller_button_start.svg"),
	JOY_BUTTON_LEFT_SHOULDER:
	preload("res://assets/kenney-input-prompts/controller_button_left_shoulder.svg"),
	JOY_BUTTON_RIGHT_SHOULDER:
	preload("res://assets/kenney-input-prompts/controller_button_right_shoulder.svg"),
	JOY_BUTTON_DPAD_LEFT: preload("res://assets/kenney-input-prompts/controller_dpad_left.svg"),
	JOY_BUTTON_DPAD_UP: preload("res://assets/kenney-input-prompts/controller_dpad_up.svg"),
	JOY_BUTTON_DPAD_RIGHT: preload("res://assets/kenney-input-prompts/controller_dpad_right.svg"),
	JOY_BUTTON_DPAD_DOWN: preload("res://assets/kenney-input-prompts/controller_dpad_down.svg"),
}
## A trigger or stick, by its axis.
const AXES: Dictionary[JoyAxis, Texture2D] = {
	JOY_AXIS_TRIGGER_LEFT:
	preload("res://assets/kenney-input-prompts/controller_trigger_left.svg"),
	JOY_AXIS_TRIGGER_RIGHT:
	preload("res://assets/kenney-input-prompts/controller_trigger_right.svg"),
}
## Touch gestures that press an action, by the action: a pinch on the Survey zooms it in or out
## (SurveyPinch, #1221).
const GESTURES: Dictionary[StringName, Texture2D] = {
	&"survey_zoom_in": preload("res://assets/kenney-input-prompts/touch_zoom_in.svg"),
	&"survey_zoom_out": preload("res://assets/kenney-input-prompts/touch_zoom_out.svg"),
}
## Pointing at something on the screen, by device: a left click (the mouse counts with the
## keyboard, DeviceInUse) or a tap (#1221). A controller can't point.
const POINTING: Dictionary[DeviceInUse.Device, Texture2D] = {
	DeviceInUse.Device.KEYBOARD: preload("res://assets/kenney-input-prompts/mouse_left.svg"),
	DeviceInUse.Device.TOUCH: preload("res://assets/kenney-input-prompts/touch_tap.svg"),
}


## The glyph of the first key, button or axis that presses `action` on `device`, or of the touch
## gesture that does, or null for none.
static func of(action: StringName, device: DeviceInUse.Device) -> Texture2D:
	if device == DeviceInUse.Device.TOUCH:
		return GESTURES.get(action)
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


## The glyph of pointing at something on the screen on `device`, a click or a tap, or null for a
## controller.
static func pointing(device: DeviceInUse.Device) -> Texture2D:
	return POINTING.get(device)
