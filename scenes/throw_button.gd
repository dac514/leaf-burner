class_name ThrowButton extends TouchScreenButton
## Large touch zone for throwing leaves, with a visible button drawn to match the VirtualJoystick.
## The whole shape reacts to touches; the drawn button is only the visual hint.

const RING_RADIUS: float = 50.0
const RING_WIDTH: float = 3.0
const PRESSED_SCALE: float = 0.86
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const RING_PRESSED_COLOR := Color(1.0, 0.85, 0.55, 1.0)
const DISC_COLOR := Color(0.1, 0.06, 0.03, 0.35)
const DISC_PRESSED_COLOR := Color(0.95, 0.45, 0.12, 0.55)

## 0 = idle, 1 = fully pressed; drives the colours of the drawn button
var press_amount: float = 0.0:
	set(value):
		press_amount = value
		if visual:
			visual.queue_redraw()
var press_tween: Tween

@onready var visual: Node2D = $Visual


func _ready() -> void:
	visual.draw.connect(_draw_visual)
	pressed.connect(_on_pressed)
	released.connect(_on_released)


func _draw_visual() -> void:
	visual.draw_circle(Vector2.ZERO, RING_RADIUS - RING_WIDTH * 0.5, DISC_COLOR.lerp(DISC_PRESSED_COLOR, press_amount))
	visual.draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 64, RING_COLOR.lerp(RING_PRESSED_COLOR, press_amount), RING_WIDTH, true)
	# Swoosh lines hint at leaves being flung
	var swoosh_color := Color(1.0, 1.0, 1.0, 0.45 + 0.4 * press_amount)
	visual.draw_arc(Vector2(6, 10), 30.0, deg_to_rad(195), deg_to_rad(265), 16, swoosh_color, 2.0, true)
	visual.draw_arc(Vector2(6, 10), 22.0, deg_to_rad(200), deg_to_rad(255), 12, swoosh_color, 2.0, true)


func _on_pressed() -> void:
	_animate_press(1.0, Vector2.ONE * PRESSED_SCALE, 0.06)


func _on_released() -> void:
	_animate_press(0.0, Vector2.ONE, 0.18)


func _animate_press(amount: float, target_scale: Vector2, duration: float) -> void:
	if press_tween:
		press_tween.kill()
	press_tween = create_tween().set_parallel()
	press_tween.tween_property(self, "press_amount", amount, duration)
	press_tween.tween_property(visual, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
