class_name Leaf extends RigidBody2D

signal leaf_burned(leaf: Leaf)

enum State { FALLING, FOLLOWING, DROPPED }

var current_state: State = State.FALLING
var player_node: CharacterBody2D
var follow_speed: float = 100.0
var spawner: LeafSpawner
var out_of_bounds_time: float = 0.0
var is_removing: bool = false

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite_2d.frame = randi() % 2
	animated_sprite_2d.pause()
	freeze = false
	gravity_scale = 1
	z_index = 3


func _physics_process(_delta: float) -> void:
	match current_state:
		State.FALLING:
			gravity_scale = 1
		State.FOLLOWING:
			# Disable collisions with other leaves while following player
			gravity_scale = 0
			linear_velocity = Vector2.ZERO
			call_deferred("set_collision_layer_value", 2, false)  # Remove from leaf layer
			call_deferred("set_collision_mask_value", 4, false)  # Don't collide with floors
			call_deferred("set_collision_mask_value", 5, false)  # Don't collide with furnaces
			animated_sprite_2d.play()
		State.DROPPED:
			# Re-enable collisions when dropped
			gravity_scale = 1
			call_deferred("set", "freeze", false)
			call_deferred("set_collision_layer_value", 2, true)  # Back to leaf layer
			call_deferred("set_collision_mask_value", 4, true)  # Collide with floors
			call_deferred("set_collision_mask_value", 5, true)  # Collide with furnaces
			animated_sprite_2d.pause()


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
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(2.25, 2.25), 0.15)
		tween.tween_property(self, "modulate:a", 0.0, 0.15)
		tween.tween_callback(cleanup_leaf)
