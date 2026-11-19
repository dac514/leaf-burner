class_name Player extends CharacterBody2D

const JUMP_VELOCITY = -400.0
const MAX_JUMPS = 4
const ACCELERATION = 1200.0
const DECELERATION = 1080.0
const TOO_MANY_LEAVES_MESSAGE_COOLDOWN: float = 20.0
const JOYSTICK_DEADZONE := 0.2
# Jumping by angle, so one thumb can run and jump: tip the stick about 30 degrees up to jump,
# drop back toward level to re-arm, rock up again to jump again (keys work the same way)
const JUMP_PRESS_SHARE: float = 0.5  # Share of the tilt pointing up needed to jump (0.5 = 30 degrees)
const JUMP_REARM_SHARE: float = 0.3  # Back below this (about 17 degrees) and the next rock jumps again
const JUMP_MIN_TILT: float = 0.25  # Ignore tiny stick wobbles near the centre
const JUMP_BUFFER_TIME: float = 0.12  # A jump pressed this long before landing still happens

# Leaf swirl: a tilted, breathing whirlwind that trails the elf
const ORBIT_BASE_RADIUS: float = 68.0
const ORBIT_RADIUS_PER_LEAF: float = 0.35  # Swirl grows as you carry more
const ORBIT_TILT: float = 0.45  # Squashes the ring into an ellipse for the 3D look
const ORBIT_CENTER_OFFSET := Vector2(0, 5)  # Main ring circles the waist and legs
const ORBIT_WOBBLE: float = 6.0
const ORBIT_FOLLOW_SHARPNESS: float = 14.0  # Higher = leaves settle into their spots faster
const ORBIT_MAX_LAG: float = 70.0  # Never sit further than this from their spot
const ORBIT_TRAIL_PER_SPEED: float = 0.04  # Swirl leans behind the elf by this much per px/s of speed
const ORBIT_MAX_TRAIL: float = 18.0  # Cap on the lean, so the elf stays centred even at top speed
const UPPER_RING_TRAIL_SCALE: float = 1.6  # Upper ring leans a bit more, like a bending tornado
const UPPER_RING_MIN_LEAVES: int = 30  # Carry this many and a second ring forms above the head
const UPPER_RING_HEIGHT: float = -125.0
const UPPER_RING_SCALE: float = 0.8
const UPPER_RING_SPEED: float = 1.5

# Throw: short wind-up, then leaves sling off the front of the swirl one after another
const WIND_UP_TIME: float = 0.1
const WIND_UP_SPIN_BOOST: float = 3.5
const MAX_RELEASE_TIME: float = 0.6
const THROW_DISTANCE: float = 400.0
const THROW_SPREAD_DEGREES: float = 15.0
const THROW_SPIN: float = 12.0  # Max tumble speed of a thrown leaf (rad/s)

@export var max_leaves: int = 100
@export var max_speed: int = 300

var collected_leaves: Array[Leaf] = []
var facing_direction: int = 1  # 1 for right, -1 for left
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var jump_count: int = 0
var jump_armed: bool = true
var jump_buffer_time: float = 0.0
var rotation_angle: float = 0.0
var rotation_speed: float = 5.0
var spin_boost: float = 1.0
var swirl_time: float = 0.0
var swirl_origin: Vector2  # Player position last frame, used to carry the swirl along
var is_throwing: bool = false
var release_active: bool = false
var release_travel: float = 0.0  # Radians the swirl has turned since release started
var release_elapsed: float = 0.0
var release_queue: Array[Dictionary] = []  # {leaf, travel, speed} waiting to reach the release point
var spin_tween: Tween
var squash_tween: Tween
var shake_tween: Tween
var gust: CPUParticles2D

# Message cooldown tracking
var last_too_many_leaves_message_time: float = -20.0

@onready var leaf_collection_area: Area2D = $LeafCollector
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var message_bar: MessageBar = %MessageBar
@onready var joystick: VirtualJoystick = %VirtualJoystick
@onready var throw_button: ThrowButton = %ThrowButton
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	leaf_collection_area.body_entered.connect(_on_leaf_collection_area_body_entered)
	# Pass `-- --touch-ui` on the command line to test the touch controls with a mouse on desktop
	var force_touch_ui: bool = "--touch-ui" in OS.get_cmdline_user_args()
	if force_touch_ui:
		Input.emulate_touch_from_mouse = true
	var is_mobile: bool = force_touch_ui or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	joystick.visible = is_mobile
	throw_button.visible = is_mobile
	swirl_origin = global_position
	gust = _create_gust()
	add_child(gust)


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

	# Handle jump (buffered, so a press just before landing still counts)
	if _read_jump_press():
		jump_buffer_time = JUMP_BUFFER_TIME
	if jump_buffer_time > 0.0 and jump_count < MAX_JUMPS:
		velocity.y = JUMP_VELOCITY
		jump_count += 1
		jump_buffer_time = 0.0
	else:
		jump_buffer_time = maxf(0.0, jump_buffer_time - delta)

	# Handle direction: any tilt past the deadzone runs at full speed, like a key
	var direction := Input.get_axis("move_left", "move_right")
	direction = signf(direction) if absf(direction) > JOYSTICK_DEADZONE else 0.0
	if direction:
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
	if release_active:
		_process_release(delta)


func _on_leaf_collection_area_body_entered(body: Node2D) -> void:
	if body is Leaf:
		var leaf: Leaf = body
		# Freshly thrown leaves launch from inside the pickup reach, so don't grab them straight back
		var can_pick_up: bool = leaf.current_state == leaf.State.FALLING or (leaf.current_state == leaf.State.DROPPED and not leaf.is_freshly_thrown())
		# Leaves that are fading out or burning are about to be freed; carrying one would leave a dead slot
		if leaf.is_removing:
			can_pick_up = false
		if not can_pick_up:
			return
		if collected_leaves.size() < max_leaves:
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


## True once per jump press. Works on the stick's angle rather than on "up" alone,
## so rocking the thumb up and back jumps repeatedly while still holding a direction.
func _read_jump_press() -> bool:
	var up: float = Input.get_action_strength("move_up")
	var stick := Vector2(Input.get_axis("move_left", "move_right"), -up)
	var up_share: float = up / stick.length() if stick.length() >= JUMP_MIN_TILT else 0.0
	if up_share <= JUMP_REARM_SHARE:
		jump_armed = true
	if jump_armed and up_share >= JUMP_PRESS_SHARE:
		jump_armed = false
		return true
	# A key tapped and released inside a single frame never shows up in the strength
	return Input.is_action_just_pressed("move_up") and up < JOYSTICK_DEADZONE


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


## Swirl collected leaves around the player like a little whirlwind
func collect_leaves(delta: float) -> void:
	swirl_time += delta
	var spin_step: float = delta * rotation_speed * spin_boost
	rotation_angle += spin_step * facing_direction
	if release_active:
		release_travel += spin_step

	var count: int = collected_leaves.size()
	var follow: float = 1.0 - exp(-ORBIT_FOLLOW_SHARPNESS * delta)
	# Carry leaves with the elf fully, so speed never leaves him at the front of the swirl
	var carried: Vector2 = global_position - swirl_origin
	swirl_origin = global_position
	var trail: Vector2 = (-velocity * ORBIT_TRAIL_PER_SPEED).limit_length(ORBIT_MAX_TRAIL)
	for i in range(count):
		var leaf: Leaf = collected_leaves[i]
		# Thrown leaves keep their slot until the throw ends, so the others don't jump around
		if leaf == null or not is_instance_valid(leaf) or leaf.current_state != Leaf.State.FOLLOWING:
			continue
		var angle: float = _orbit_angle(i, count)
		var lean: Vector2 = trail * (UPPER_RING_TRAIL_SCALE if _is_upper_ring(i, count) else 1.0)
		var target: Vector2 = global_position + _orbit_offset(i, count, angle) + lean
		# Ease toward the slot so new leaves swoop in and the swirl stays soft
		var next_position: Vector2 = (leaf.global_position + carried).lerp(target, follow)
		var lag: Vector2 = next_position - target
		if lag.length() > ORBIT_MAX_LAG:
			next_position = target + lag.normalized() * ORBIT_MAX_LAG
		leaf.global_position = next_position

		# Fake depth: the lower half of the ellipse is nearer the camera
		var depth: float = (sin(angle) + 1.0) * 0.5
		leaf.z_index = 4 if depth > 0.5 else 0
		leaf.animated_sprite_2d.scale = Vector2.ONE * lerpf(0.75, 1.2, depth)
		var shade: float = lerpf(0.6, 1.0, depth)
		leaf.animated_sprite_2d.modulate = Color(shade, shade, shade)


func _is_upper_ring(index: int, count: int) -> bool:
	return count >= UPPER_RING_MIN_LEAVES and index % 3 == 0


func _orbit_angle(index: int, count: int) -> float:
	var spin: float = rotation_angle * (UPPER_RING_SPEED if _is_upper_ring(index, count) else 1.0)
	return (index / float(count)) * TAU + spin


func _orbit_offset(index: int, count: int, angle: float) -> Vector2:
	var radius: float = ORBIT_BASE_RADIUS + count * ORBIT_RADIUS_PER_LEAF
	var height: float = 0.0
	if _is_upper_ring(index, count):
		radius *= UPPER_RING_SCALE
		height = UPPER_RING_HEIGHT
	# Golden-ratio spread gives every leaf a slightly different height and width, so it's a loose band
	var band: float = fposmod(index * 0.618034, 1.0)
	radius *= lerpf(1.08, 0.92, band)
	radius += sin(swirl_time * 3.0 + index * 1.7) * ORBIT_WOBBLE
	height += lerpf(-12.0, 12.0, band)
	return ORBIT_CENTER_OFFSET + Vector2(cos(angle) * radius, sin(angle) * radius * ORBIT_TILT + height)


## Wind up, then sling the leaves off the front of the swirl
func throw_leaves() -> void:
	if is_throwing or collected_leaves.is_empty():
		return
	is_throwing = true

	# Wind-up: the swirl whips faster while the elf crouches
	if spin_tween:
		spin_tween.kill()
	spin_tween = create_tween()
	spin_tween.tween_property(self, "spin_boost", WIND_UP_SPIN_BOOST, WIND_UP_TIME).set_ease(Tween.EASE_IN)
	spin_tween.tween_callback(_start_release)
	_squash(Vector2(1.12, 0.88), WIND_UP_TIME, Tween.TRANS_SINE)


func _start_release() -> void:
	# Leaves fly off one by one as they swing past the front-top of the swirl
	var release_angle: float = atan2(-0.87, 0.5 * facing_direction)
	var count: int = collected_leaves.size()
	release_queue.clear()
	for i in range(count):
		var leaf: Leaf = collected_leaves[i]
		if leaf == null or not is_instance_valid(leaf) or leaf.current_state != Leaf.State.FOLLOWING:
			continue
		var speed: float = UPPER_RING_SPEED if _is_upper_ring(i, count) else 1.0
		var travel: float = fposmod((release_angle - _orbit_angle(i, count)) * facing_direction, TAU)
		release_queue.append({"leaf": leaf, "travel": travel, "speed": speed})
	release_travel = 0.0
	release_elapsed = 0.0
	release_active = true

	var strength: float = clampf(float(release_queue.size()) / max_leaves, 0.2, 1.0)
	_squash(Vector2(0.86, 1.16), 0.0, Tween.TRANS_LINEAR)
	_squash(Vector2.ONE, 0.35, Tween.TRANS_ELASTIC)
	_shake_camera(lerpf(2.0, 7.0, strength), 0.2)
	gust.global_position = global_position + Vector2(facing_direction * 45.0, -55.0)
	gust.direction = Vector2(facing_direction, -0.35)
	gust.amount = int(lerpf(6.0, 16.0, strength))
	gust.restart()


func _process_release(delta: float) -> void:
	release_elapsed += delta
	var force_all: bool = release_elapsed >= MAX_RELEASE_TIME
	var still_waiting: Array[Dictionary] = []
	for entry in release_queue:
		var leaf: Leaf = entry["leaf"]
		if leaf == null or not is_instance_valid(leaf) or leaf.current_state != Leaf.State.FOLLOWING:
			continue
		if force_all or release_travel * float(entry["speed"]) >= float(entry["travel"]):
			_launch_leaf(leaf)
		else:
			still_waiting.append(entry)
	release_queue = still_waiting
	if release_queue.is_empty():
		_finish_throw()


func _launch_leaf(leaf: Leaf) -> void:
	leaf.current_state = leaf.State.DROPPED
	leaf.thrown_time_msec = Time.get_ticks_msec()
	leaf.z_index = 3
	leaf.animated_sprite_2d.scale = Vector2.ONE
	leaf.animated_sprite_2d.modulate = Color.WHITE
	leaf.freeze = false  # Unfreeze now so the launch velocity isn't lost

	var spread: float = deg_to_rad(randf_range(-THROW_SPREAD_DEGREES, THROW_SPREAD_DEGREES))
	var throw_direction: Vector2 = Vector2(facing_direction, -0.5).normalized().rotated(spread)
	var launch_velocity: Vector2 = throw_direction * THROW_DISTANCE * 3.5 + velocity * 0.3
	launch_velocity.y = min(launch_velocity.y, -200.0)
	leaf.linear_velocity = launch_velocity
	leaf.angular_velocity = randf_range(-THROW_SPIN, THROW_SPIN)


func _finish_throw() -> void:
	release_active = false
	is_throwing = false
	# Keep any leaves picked up during the throw; drop the ones that flew off
	# (Untyped on purpose: a freed leaf can't be passed as a typed Leaf, and that used to break this cleanup)
	var still_carried: Array[Leaf] = []
	for i in range(collected_leaves.size()):
		var item: Variant = collected_leaves[i]
		if is_instance_valid(item) and (item as Leaf).current_state == Leaf.State.FOLLOWING:
			still_carried.append(item as Leaf)
	collected_leaves = still_carried
	update_player_outline()
	if spin_tween:
		spin_tween.kill()
	spin_tween = create_tween()
	spin_tween.tween_property(self, "spin_boost", 1.0, 0.3).set_ease(Tween.EASE_OUT)


func _squash(target_scale: Vector2, duration: float, transition: Tween.TransitionType) -> void:
	if squash_tween:
		squash_tween.kill()
	if duration <= 0.0:
		animated_sprite_2d.scale = target_scale
		return
	squash_tween = create_tween()
	squash_tween.tween_property(animated_sprite_2d, "scale", target_scale, duration).set_trans(transition).set_ease(Tween.EASE_OUT)


func _shake_camera(strength: float, duration: float) -> void:
	if shake_tween:
		shake_tween.kill()
	shake_tween = create_tween()
	shake_tween.tween_method(
		func(progress: float) -> void:
			var falloff: float = (1.0 - progress) * strength
			camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * falloff,
		0.0,
		1.0,
		duration
	)
	shake_tween.tween_callback(func() -> void: camera.offset = Vector2.ZERO)


## A puff of air where the leaves are flung from
func _create_gust() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.lifetime = 0.45
	particles.local_coords = false
	particles.z_index = 3
	particles.texture = preload("res://assets/smoke_02.png")
	particles.spread = 28.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 220.0
	particles.initial_velocity_max = 420.0
	particles.damping_min = 500.0
	particles.damping_max = 700.0
	particles.scale_amount_min = 0.05
	particles.scale_amount_max = 0.11
	particles.angle_min = -180.0
	particles.angle_max = 180.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.97, 0.9, 0.55))
	fade.set_color(1, Color(1.0, 0.95, 0.85, 0.0))
	particles.color_ramp = fade
	return particles
