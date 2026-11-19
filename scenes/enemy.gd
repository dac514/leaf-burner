class_name Enemy extends CharacterBody2D

signal enemy_hit_player(enemy: Enemy)

@export var base_speed: float = 150.0
@export var arc_strength: float = 50.0
## How far each thrown leaf that hits the owl bends its flight away from the player
@export var deflect_per_leaf_degrees: float = 0.6
## Cap on the total bend, so a big throw helps but never makes owls harmless
@export var max_deflect_degrees: float = 18.0

var direction: int = 1  # 1 for moving right, -1 for moving left
var player_node: Player
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var initial_y: float
var is_dying: bool = false
var is_charging: bool = false
var charge_velocity: Vector2 = Vector2.ZERO
var time_off_screen: float = 0.0
var is_off_screen: bool = false
var deflection: float = 0.0  # Radians of bend accumulated from leaf hits
var flinch_tween: Tween

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var visibility_notifier: VisibleOnScreenNotifier2D = $VisibilityNotifier2D
@onready var leaf_detector: Area2D = $LeafDetector


func _ready() -> void:
	initial_y = global_position.y

	# Connect visibility notifier to track off-screen status
	visibility_notifier.connect("screen_exited", _on_screen_exited)
	visibility_notifier.connect("screen_entered", _on_screen_entered)
	leaf_detector.body_entered.connect(_on_leaf_detector_body_entered)

	# Start the flying animation
	animated_sprite.play("fly")


func set_player(player: Player) -> void:
	player_node = player


func _physics_process(delta: float) -> void:
	if is_dying:
		return

	# Move horizontally (or charge if charging)
	if is_charging:
		# Continue straight line charge
		velocity = charge_velocity
	else:
		velocity.x = direction * base_speed

	# Check for charge opportunity
	if player_node and is_instance_valid(player_node) and not is_charging:
		var player_pos: Vector2 = player_node.global_position
		var distance_to_player: float = global_position.distance_to(player_pos)

		if distance_to_player < 320.0:
			# Start charging in straight line toward player
			is_charging = true
			var charge_direction: Vector2 = (player_pos - global_position).normalized()
			# Leaves that hit the owl before it charged still throw off its aim
			charge_direction = _steer_away_from_player(charge_direction, deflection)
			charge_velocity = charge_direction * base_speed * 2.25
		else:
			# Add subtle curve toward player when not charging
			var y_diff: float = player_pos.y - global_position.y
			var curve_force: float = (y_diff / distance_to_player) * arc_strength * 0.3
			velocity.y += curve_force * delta

	# Apply some gravity when not charging
	if not is_charging:
		velocity.y += gravity * 0.1 * delta

	move_and_slide()

	# Track time off screen for delayed cleanup
	if is_off_screen:
		time_off_screen += delta
		# Only cleanup after being off screen for 3 seconds
		if time_off_screen > 3.0:
			queue_free()

	# Check for collision with player
	for i in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is Player:
			_hit_player()
			break


func set_direction(new_direction: int) -> void:
	direction = new_direction


func _hit_player() -> void:
	if is_dying:
		return

	is_dying = true
	enemy_hit_player.emit(self)
	if flinch_tween:
		flinch_tween.kill()

	# Spinning fade animation
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation", rotation + TAU * 2, 0.5)
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.5)
	# Remove after animation
	tween.tween_callback(queue_free).set_delay(0.5)


func _on_leaf_detector_body_entered(body: Node2D) -> void:
	if is_dying or not body is Leaf:
		return
	var leaf: Leaf = body as Leaf
	if not leaf.is_freshly_thrown():
		return  # Only leaves in flight from a throw count, not resting or falling ones

	_flinch()
	var step: float = min(deg_to_rad(deflect_per_leaf_degrees), deg_to_rad(max_deflect_degrees) - deflection)
	if step <= 0.0:
		return
	deflection += step
	if is_charging:
		charge_velocity = _steer_away_from_player(charge_velocity, step)
	else:
		# Not charging yet: a little lift keeps it higher above the player
		velocity.y -= 10.0


## Rotate a direction by angle, choosing the way that bends it away from the player
func _steer_away_from_player(vector: Vector2, angle: float) -> Vector2:
	if angle == 0.0:
		return vector
	var away: Vector2 = Vector2.UP
	if player_node and is_instance_valid(player_node):
		away = global_position - player_node.global_position
	# Positive rotation turns toward whichever side the cross product points
	var turn_sign: float = signf(vector.cross(away))
	if turn_sign == 0.0:
		turn_sign = 1.0
	return vector.rotated(angle * turn_sign)


## Quick warm flash and squash so the player sees their leaves landing
func _flinch() -> void:
	if flinch_tween:
		flinch_tween.kill()
	animated_sprite.modulate = Color(1.8, 1.4, 1.0)
	animated_sprite.scale = Vector2(1.15, 0.85)
	flinch_tween = create_tween().set_parallel()
	flinch_tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.2)
	flinch_tween.tween_property(animated_sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_screen_exited() -> void:
	# Mark as off screen but don't cleanup immediately
	is_off_screen = true
	time_off_screen = 0.0


func _on_screen_entered() -> void:
	# Reset off-screen timer when enemy comes back into view
	is_off_screen = false
	time_off_screen = 0.0
