class_name InputGlyphs
extends RefCounted
## The glyph of the key, button or axis that presses an InputMap action on a device (#583): a
## white shape, drawn in ink like the UI's icons. It reads the action's own events, so a hint always
## shows what the InputMap says. Only the glyphs a hint shows are in the game: a key or button
## without one shows none, and so does touch, whose hints are the buttons tapped, but for the
## gestures that press an action too (GESTURES). Pointing at the screen, a click or a tap, has its
## own glyph (pointing). Each glyph is named by its id, which ResourcePacks resolves.

## The left stick, which walks the player whichever way it's pushed (MoveHint, #1222). The right
## stick has no glyph while nothing is bound to it.
const STICK_LEFT: String = "prompt_controller_stick_left"
## A drag on the screen, which steers the touch stick and so walks the player (TouchStick, #1222).
const DRAG: String = "prompt_touch_drag"
const KEYS: Dictionary[Key, String] = {
	KEY_1: "prompt_keyboard_1",
	KEY_2: "prompt_keyboard_2",
	KEY_3: "prompt_keyboard_3",
	KEY_EQUAL: "prompt_keyboard_equals",
	KEY_MINUS: "prompt_keyboard_minus",
	KEY_TAB: "prompt_keyboard_tab",
	KEY_ENTER: "prompt_keyboard_enter",
	KEY_ESCAPE: "prompt_keyboard_escape",
	KEY_E: "prompt_keyboard_e",
	KEY_F: "prompt_keyboard_f",
	KEY_Q: "prompt_keyboard_q",
	KEY_R: "prompt_keyboard_r",
	KEY_T: "prompt_keyboard_t",
	KEY_V: "prompt_keyboard_v",
	KEY_W: "prompt_keyboard_w",
	KEY_A: "prompt_keyboard_a",
	KEY_S: "prompt_keyboard_s",
	KEY_D: "prompt_keyboard_d",
	KEY_X: "prompt_keyboard_x",
}
const BUTTONS: Dictionary[JoyButton, String] = {
	JOY_BUTTON_A: "prompt_controller_button_a",
	JOY_BUTTON_B: "prompt_controller_button_b",
	JOY_BUTTON_X: "prompt_controller_button_x",
	JOY_BUTTON_Y: "prompt_controller_button_y",
	JOY_BUTTON_BACK: "prompt_controller_button_back",
	JOY_BUTTON_START: "prompt_controller_button_start",
	JOY_BUTTON_LEFT_SHOULDER:
	"prompt_controller_button_left_shoulder",
	JOY_BUTTON_RIGHT_SHOULDER:
	"prompt_controller_button_right_shoulder",
	JOY_BUTTON_DPAD_LEFT: "prompt_controller_dpad_left",
	JOY_BUTTON_DPAD_UP: "prompt_controller_dpad_up",
	JOY_BUTTON_DPAD_RIGHT: "prompt_controller_dpad_right",
	JOY_BUTTON_DPAD_DOWN: "prompt_controller_dpad_down",
}
## A trigger or stick, by its axis.
const AXES: Dictionary[JoyAxis, String] = {
	JOY_AXIS_LEFT_X: STICK_LEFT,
	JOY_AXIS_LEFT_Y: STICK_LEFT,
	JOY_AXIS_TRIGGER_LEFT:
	"prompt_controller_trigger_left",
	JOY_AXIS_TRIGGER_RIGHT:
	"prompt_controller_trigger_right",
}
## Touch gestures that press an action, by the action: a pinch on the Survey zooms it in or out
## (SurveyPinch, #1221), and a drag walks the player (DRAG).
const GESTURES: Dictionary[StringName, String] = {
	&"move_up": DRAG,
	&"move_left": DRAG,
	&"move_down": DRAG,
	&"move_right": DRAG,
	&"survey_zoom_in": "prompt_touch_zoom_in",
	&"survey_zoom_out": "prompt_touch_zoom_out",
}
## Pointing at something on the screen, by device: a left click (the mouse counts with the
## keyboard, DeviceInUse) or a tap (#1221). A controller can't point.
const POINTING: Dictionary[DeviceInUse.Device, String] = {
	DeviceInUse.Device.KEYBOARD: "prompt_mouse_left",
	DeviceInUse.Device.TOUCH: "prompt_touch_tap",
}


## The glyph of the first key, button or axis that presses `action` on `device`, or of the touch
## gesture that does, or null for none.
static func of(action: StringName, device: DeviceInUse.Device) -> Texture2D:
	if device == DeviceInUse.Device.TOUCH:
		var gesture: String = GESTURES.get(action, "")
		return _texture(gesture)
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		var glyph: String = _glyph(event, device)
		if not glyph.is_empty():
			return _texture(glyph)
	return null


## The glyph of pointing at something on the screen on `device`, a click or a tap, or null for a
## controller.
static func pointing(device: DeviceInUse.Device) -> Texture2D:
	var glyph: String = POINTING.get(device, "")
	return _texture(glyph)


## The id of `event`'s glyph on `device`, or "" when it's another device's or has none.
static func _glyph(event: InputEvent, device: DeviceInUse.Device) -> String:
	var key: InputEventKey = event as InputEventKey
	if key != null and device == DeviceInUse.Device.KEYBOARD:
		# An action names a key by where it lies (WASD) or by what it says (Enter).
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return KEYS.get(code, "")
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null and device == DeviceInUse.Device.CONTROLLER:
		return BUTTONS.get(button.button_index, "")
	var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if motion != null and device == DeviceInUse.Device.CONTROLLER:
		return AXES.get(motion.axis, "")
	return ""


## The glyph whose id is `glyph` (ResourcePacks), or null for "".
static func _texture(glyph: String) -> Texture2D:
	return null if glyph.is_empty() else ResourcePacks.texture(glyph)
