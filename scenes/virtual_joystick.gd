extends VirtualJoystick
## Ignores mouse input while a finger is holding the stick.
##
## In web builds the browser also reports every finger's movement as mouse motion, with no
## finger index. While held, VirtualJoystick follows any mouse motion, so a second finger
## (e.g. the left thumb mashing throw) dragged the stick toward itself and turned the elf
## around. Real touches are tracked by finger index and keep working. With no finger on the
## stick the mouse still works, so desktop testing with `-- --touch-ui` is unaffected.

var held_by_touch: int = -1  # Index of the real finger holding the stick, or -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		# Touches Godot makes up from the mouse don't count; the joystick ignores those itself
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed and held_by_touch == -1 and Rect2(Vector2.ZERO, size).has_point(touch.position):
			held_by_touch = touch.index
		elif not touch.pressed and touch.index == held_by_touch:
			held_by_touch = -1
		return
	if held_by_touch != -1 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		accept_event()  # Stops the built-in joystick handling from seeing it
