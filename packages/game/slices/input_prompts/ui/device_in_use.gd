class_name DeviceInUse
extends Node
## Which device the player plays with now (#583): the one that sent the last input, so the hints
## show its keys or buttons (InputGlyphs). The keyboard and the mouse count as one device, since
## they're used together. The node stands last in the main scene, so it hears every event before
## any other node can take it; Godot's own touch and mouse stand-ins (a touch made from a click, a
## click made from a touch) don't count, nor does a stick or trigger that presses no action yet.

enum Device {
	KEYBOARD,
	CONTROLLER,
	TOUCH,
}

## The device in use: touch on phones and tablets, the keyboard elsewhere, until another is used.
static var device: Device = Device.TOUCH if _touch_first() else Device.KEYBOARD


func _input(event: InputEvent) -> void:
	heard(event)


## Takes `event`'s device as the one in use, if it's a device's own input.
static func heard(event: InputEvent) -> void:
	var made_up: bool = event.device == InputEvent.DEVICE_ID_EMULATION
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not made_up:
			device = Device.TOUCH
	elif event is InputEventMouseButton:
		if not made_up:
			device = Device.KEYBOARD
	elif event is InputEventKey:
		device = Device.KEYBOARD
	elif event is InputEventJoypadButton:
		device = Device.CONTROLLER
	elif event is InputEventJoypadMotion:
		if _presses_an_action(event):
			device = Device.CONTROLLER


## Whether `event` is past the deadzone of an action it presses (#1423): a push that walks the
## player counts, drift inside every deadzone doesn't.
static func _presses_an_action(event: InputEvent) -> bool:
	for action: StringName in InputMap.get_actions():
		if event.is_action_pressed(action):
			return true
	return false


## Whether this build runs where touch is the usual input: phones and tablets, natively or in a
## browser.
static func _touch_first() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
