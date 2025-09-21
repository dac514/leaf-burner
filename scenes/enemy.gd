class_name Enemy extends CharacterBody2D

signal enemy_hit_player(enemy: Enemy)

@export var base_speed: float = 150.0
@export var arc_strength: float = 50.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var visibility_notifier: VisibleOnScreenNotifier2D = $VisibilityNotifier2D

var direction: int = 1  # 1 for moving right, -1 for moving left
var player_node: Player
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var initial_y: float
var is_dying: bool = false
var is_charging: bool = false
var charge_velocity: Vector2 = Vector2.ZERO
var time_off_screen: float = 0.0
var is_off_screen: bool = false

func _ready() -> void:
	initial_y = global_position.y

	# Connect visibility notifier to track off-screen status
	visibility_notifier.connect("screen_exited", _on_screen_exited)
	visibility_notifier.connect("screen_entered", _on_screen_entered)

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

	# Spinning fade animation
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation", rotation + TAU * 2, 0.5)
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.5)
	# Remove after animation
	tween.tween_callback(queue_free).set_delay(0.5)


func _on_screen_exited() -> void:
	# Mark as off screen but don't cleanup immediately
	is_off_screen = true
	time_off_screen = 0.0

func _on_screen_entered() -> void:
	# Reset off-screen timer when enemy comes back into view
	is_off_screen = false
	time_off_screen = 0.0
