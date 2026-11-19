class_name Player extends CharacterBody2D

const JUMP_VELOCITY = -400.0
const MAX_JUMPS = 4
const ACCELERATION = 1200.0
const DECELERATION = 1080.0
const TOO_MANY_LEAVES_MESSAGE_COOLDOWN: float = 20.0
const JOYSTICK_DEADZONE := 0.2

@export var max_leaves: int = 100
@export var max_speed: int = 300

var collected_leaves: Array[Leaf] = []
var facing_direction: int = 1  # 1 for right, -1 for left
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var jump_count: int = 0
var rotation_angle: float = 0.0
var rotation_speed: float = 5.0

# Message cooldown tracking
var last_too_many_leaves_message_time: float = -20.0

@onready var leaf_collection_area: Area2D = $LeafCollector
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var message_bar: MessageBar = %MessageBar
@onready var joystick: VirtualJoystick = %VirtualJoystick
@onready var throwButton: TouchScreenButton = %TouchScreenButton


func _ready() -> void:
	leaf_collection_area.body_entered.connect(_on_leaf_collection_area_body_entered)
	var is_mobile: bool = DisplayServer.is_touchscreen_available()
	joystick.visible = is_mobile
	throwButton.visible = is_mobile


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		# Add the gravity
		velocity.y += gravity * delta
	else:
		# Reset jump count when on the floor
		jump_count = 0

	# Handle drop
	if Input.is_action_just_pressed("throw_leaves"):
		throw_leaves()

	# Handle jump
	if Input.is_action_just_pressed("move_up") and jump_count < MAX_JUMPS:
		velocity.y = JUMP_VELOCITY
		jump_count += 1

	# Handle direction
	var direction := Input.get_axis("move_left", "move_right")
	if abs(direction) > JOYSTICK_DEADZONE:
		var desired_velocity_x: float = direction * max_speed
		velocity.x = move_toward(velocity.x, desired_velocity_x, ACCELERATION * delta)
		facing_direction = sign(direction)
		animated_sprite_2d.flip_h = direction > 0
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)

	# Handle animations based on state
	if not is_on_floor():
		# Player is jumping/in air
		if animated_sprite_2d.animation != "jump":
			animated_sprite_2d.play("jump")
	else:
		# Player is on ground
		if direction:
			# Player is moving
			if animated_sprite_2d.animation != "default" or not animated_sprite_2d.is_playing():
				animated_sprite_2d.play("default")
		else:
			# Player is idle
			if animated_sprite_2d.is_playing():
				animated_sprite_2d.play("idle")

	move_and_slide()
	collect_leaves(delta)


func _on_leaf_collection_area_body_entered(body: Node2D) -> void:
	if body is Leaf:
		var leaf: Leaf = body
		if collected_leaves.size() < max_leaves and (leaf.current_state == leaf.State.FALLING or leaf.current_state == leaf.State.DROPPED):
			leaf.current_state = leaf.State.FOLLOWING
			leaf.player_node = self
			leaf.z_index = 4
			leaf.call_deferred("set", "freeze", true)
			collected_leaves.append(leaf)
			update_player_outline()
		else:
			# Check if enough time has passed since last "too many leaves" message
			var current_time: float = Time.get_ticks_msec() / 1000.0
			if current_time - last_too_many_leaves_message_time >= TOO_MANY_LEAVES_MESSAGE_COOLDOWN:
				message_bar.set_text("You're carrying too many leaves, throw them!")
				last_too_many_leaves_message_time = current_time


## Update player outline based on collected leaves count
func update_player_outline() -> void:
	var shader_material: ShaderMaterial = animated_sprite_2d.material as ShaderMaterial
	if shader_material == null:
		return

	var leaf_count: int = collected_leaves.size()
	var progress: float = float(leaf_count) / float(max_leaves)

	# Color transitions from black (0,0,0) to yellow (1,1,0)
	# Start with red, then add green for a more vibrant transition
	# Red increases faster, Green starts later, Alpha transitions from 0 to 1
	var red_value: float = min(progress * 1.5, 1.0)
	var green_value: float = max(0.0, (progress - 0.3) * 1.43)
	var blue_value: float = 0.0
	var alpha_value: float = progress
	shader_material.set_shader_parameter("color", Color(red_value, green_value, blue_value, alpha_value))

	# Width transitions from 1.0 to 3.0
	var width_value: float = 1.0 + (progress * 2.0)
	shader_material.set_shader_parameter("width", width_value)


## Position collected leaves in a circle around the player
func collect_leaves(delta: float) -> void:
	var radius := 75.0  # Adjust this radius as needed
	# Rotate in the direction the player is facing
	rotation_angle += delta * rotation_speed * facing_direction

	# Create a copy of the array to prevent modification during iteration
	var leaves_to_position: Array[Leaf] = collected_leaves.duplicate()
	for i in range(leaves_to_position.size()):
		var leaf: Leaf = leaves_to_position[i]
		# Check if leaf is still in our collection and valid
		if leaf != null and is_instance_valid(leaf):
			var angle := (i / float(leaves_to_position.size())) * 2 * PI + rotation_angle
			var offset := Vector2(cos(angle), sin(angle)) * radius
			leaf.global_position = global_position + offset


## Throw the leaves away from the player
func throw_leaves() -> void:
	# Create a copy to safely iterate while modifying the original array
	var leaves_to_drop: Array[Leaf] = collected_leaves.duplicate()
	collected_leaves.clear()
	update_player_outline()

	for i in range(leaves_to_drop.size()):
		var leaf: Leaf = leaves_to_drop[i]
		if leaf == null or not is_instance_valid(leaf):
			continue

		# Store the leaf's current position (where it's rotating around player)
		var start_position := leaf.global_position

		# Calculate final throw destination
		var throw_distance := 400.0
		var throw_angle := randf_range(-15, 15)  # Random angle spread in degrees
		var throw_angle_rad := deg_to_rad(throw_angle)

		# Calculate throw direction
		var vertical_component := -0.5
		var base_direction := Vector2(facing_direction, vertical_component).normalized()
		var rotated_direction := base_direction.rotated(throw_angle_rad)

		# Calculate the target position for the throw
		var target_offset := Vector2(facing_direction * 120, -50)
		var target_position := global_position + target_offset

		# Set leaf state to dropped immediately
		leaf.current_state = leaf.State.DROPPED
		leaf.z_index = 3

		# Small delay between each leaf for staggered effect
		_animate_leaf_throw(leaf, start_position, target_position, rotated_direction, throw_distance)
		await get_tree().create_timer(0.005).timeout


# Animate leaf throwing
func _animate_leaf_throw(leaf: Leaf, start_pos: Vector2, target_pos: Vector2, throw_direction: Vector2, throw_distance: float) -> void:
	if leaf == null or not is_instance_valid(leaf):
		return

	var tween := create_tween()
	var animation_duration := 0.1

	# Use a WeakRef to safely reference the leaf
	var leaf_ref: WeakRef = weakref(leaf)

	# Animate to the throw starting position
	tween.tween_method(
		func(pos: Vector2) -> void:
			var leaf_obj: Leaf = leaf_ref.get_ref()
			if leaf_obj != null:
				leaf_obj.global_position = pos,
		start_pos,
		target_pos,
		animation_duration
	)

	# Apply throw velocity after animation
	tween.tween_callback(
		func() -> void:
			var leaf_obj: Leaf = leaf_ref.get_ref()
			if leaf_obj != null:
				var base_throw_velocity := throw_direction * throw_distance * 3.5
				var combined_velocity := base_throw_velocity + velocity * 0.3
				combined_velocity.y = min(combined_velocity.y, -200.0)
				leaf_obj.linear_velocity = combined_velocity
	)
