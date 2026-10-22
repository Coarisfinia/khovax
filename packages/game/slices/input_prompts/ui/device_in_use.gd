class_name DeviceInUse
extends Node
## Which device the player plays with now (#583): the one that sent the last input, so the hints
## show its keys or buttons (InputGlyphs). The keyboard and the mouse count as one device, since
## they're used together. The node stands last in the main scene, so it hears every event before
## any other node can take it; Godot's own touch and mouse stand-ins (a touch made from a click, a
## click made from a touch) don't count, nor does a stick barely off its rest.

enum Device {
	KEYBOARD,
	CONTROLLER,
	TOUCH,
}

## How far a stick or trigger has to move to count as the controller being used.
const DEADZONE: float = 0.5

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
		if absf((event as InputEventJoypadMotion).axis_value) > DEADZONE:
			device = Device.CONTROLLER


## Whether this build runs where touch is the usual input: phones and tablets, natively or in a
## browser.
static func _touch_first() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
