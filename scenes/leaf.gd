class_name Leaf extends RigidBody2D

signal leaf_burned(leaf: Leaf)

enum State { FALLING, FOLLOWING, DROPPED }

const FLUTTER_SPEED: float = 9.0  # How fast a thrown leaf flips over in flight
const FLUTTER_MIN_SPEED: float = 80.0  # Below this the leaf settles flat
const EMBER_GLOW_DISTANCE: float = 260.0  # Thrown leaves start glowing this close to a barrel
const EMBER_COLOR := Color(2.0, 1.1, 0.45)
const BURN_FLASH_COLOR := Color(2.4, 1.4, 0.6)

var current_state: State = State.FALLING
var player_node: CharacterBody2D
var follow_speed: float = 100.0
var spawner: LeafSpawner
var out_of_bounds_time: float = 0.0
var is_removing: bool = false
var thrown_time_msec: int = -100000
var flutter_phase: float = 0.0
var applied_state: int = -1  # Last state whose physics settings were applied

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite_2d.frame = randi() % 2
	# Flat leaves come to rest level, so tilt the art a little for a natural-looking pile
	animated_sprite_2d.rotation = randf_range(-0.6, 0.6)
	animated_sprite_2d.pause()
	freeze = false
	gravity_scale = 1
	z_index = 3
	flutter_phase = randf() * TAU


func _physics_process(delta: float) -> void:
	# Apply each state's physics settings once on change. Re-applying them every frame
	# kept resting leaves awake and cost a handful of deferred calls per leaf per frame.
	if current_state != applied_state:
		applied_state = current_state
		_apply_state()
	if current_state == State.DROPPED:
		_animate_flight(delta)


func _apply_state() -> void:
	match current_state:
		State.FALLING:
			gravity_scale = 1
		State.FOLLOWING:
			# Disable collisions with other leaves while following player
			gravity_scale = 0
			linear_velocity = Vector2.ZERO
			call_deferred("set_collision_layer_value", 2, false)  # Remove from leaf layer
			call_deferred("set_collision_mask_value", 2, false)  # Don't plough through resting leaves
			call_deferred("set_collision_mask_value", 4, false)  # Don't collide with floors
			call_deferred("set_collision_mask_value", 5, false)  # Don't collide with furnaces
			animated_sprite_2d.play()
		State.DROPPED:
			# Re-enable collisions when dropped
			gravity_scale = 1
			call_deferred("set", "freeze", false)
			call_deferred("set_collision_layer_value", 2, true)  # Back to leaf layer
			call_deferred("set_collision_mask_value", 2, true)  # Land on other leaves again
			call_deferred("set_collision_mask_value", 4, true)  # Collide with floors
			call_deferred("set_collision_mask_value", 5, true)  # Collide with furnaces
			animated_sprite_2d.pause()


## Thrown leaves flip over as they fly and glow like embers as they near a barrel
func _animate_flight(delta: float) -> void:
	if is_removing:
		return
	var sprite_scale: Vector2 = animated_sprite_2d.scale
	var speed: float = linear_velocity.length()
	if speed > FLUTTER_MIN_SPEED:
		# Squeezing scale.x through zero fakes a leaf turning over in 3D; slower leaves flutter slower
		flutter_phase += delta * FLUTTER_SPEED * clampf(speed / 600.0, 0.4, 1.5)
		var flip: float = cos(flutter_phase)
		sprite_scale.x = flip if absf(flip) > 0.15 else (0.15 if flip >= 0.0 else -0.15)
		animated_sprite_2d.scale = sprite_scale
	elif absf(sprite_scale.x) < 1.0:
		sprite_scale.x = move_toward(sprite_scale.x, 1.0 if sprite_scale.x >= 0.0 else -1.0, delta * 4.0)
		animated_sprite_2d.scale = sprite_scale

	if is_freshly_thrown() and spawner:
		var distance_to_barrel: float = minf(global_position.x - spawner.left_bound_x, spawner.right_bound_x - global_position.x)
		var glow: float = clampf(1.0 - distance_to_barrel / EMBER_GLOW_DISTANCE, 0.0, 1.0)
		animated_sprite_2d.modulate = Color.WHITE.lerp(EMBER_COLOR, glow)
	elif animated_sprite_2d.modulate != Color.WHITE:
		animated_sprite_2d.modulate = animated_sprite_2d.modulate.lerp(Color.WHITE, minf(delta * 4.0, 1.0))


## True for a little while after the player throws this leaf (while it's still in flight)
func is_freshly_thrown() -> bool:
	return current_state == State.DROPPED and Time.get_ticks_msec() - thrown_time_msec < 1500


func cleanup_leaf() -> void:
	if spawner:
		spawner.remove_leaf(self)
	queue_free()


## Quietly fade out and remove a leaf the player can no longer reach (no points awarded)
func despawn() -> void:
	if is_removing:
		return
	is_removing = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(cleanup_leaf)


func try_burn() -> void:
	# Only burn if we're in DROPPED state
	if current_state == State.DROPPED and not is_removing:
		is_removing = true
		leaf_burned.emit(self)
		# Scale and fade before cleanup
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		animated_sprite_2d.modulate = BURN_FLASH_COLOR
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(2.25, 2.25), 0.15)
		tween.tween_property(self, "modulate:a", 0.0, 0.15)
		tween.tween_callback(cleanup_leaf)
