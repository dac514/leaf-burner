class_name EnemySpawner extends Node2D

signal enemy_spawned(enemy: Enemy)

@export var enemy_scene: PackedScene  = preload("res://scenes/enemy.tscn")
@export var spawn_interval: float = 5.0  # Start with 1 enemy every 5 seconds
@export var spawn_acceleration: float = 0.1  # How much faster spawning gets over time
@export var min_spawn_interval: float = 1.0  # Minimum time between spawns
@export var spawn_y_variance: float = 150  # How much Y position can vary (up/down)
@export var spawn_x_offset: float = 50  # How far off screen to spawn

var time_since_last_spawn: float = 0.0
var game_time: float = 0.0
var active_enemies: Array[Enemy] = []

func _process(delta: float) -> void:
	game_time += delta

	# Clean up invalid enemy references
	var valid_enemies: Array[Enemy] = []
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			valid_enemies.append(enemy)
	active_enemies = valid_enemies

	# Calculate current spawn interval (gets faster over time)
	var current_interval: float = max(spawn_interval - (game_time * spawn_acceleration), min_spawn_interval)

	time_since_last_spawn += delta
	if time_since_last_spawn >= current_interval:
		spawn_enemy()
		time_since_last_spawn = 0.0


func spawn_enemy() -> void:
	if enemy_scene:
		var enemy: Enemy = enemy_scene.instantiate()

		# Get the player reference from the main scene
		var player: Player = get_parent().get_node("Player") as Player

		# Get the camera position to spawn relative to current view
		var camera: Camera2D = get_viewport().get_camera_2d()
		var camera_pos: Vector2 = Vector2.ZERO
		if camera:
			camera_pos = camera.global_position

		# Get viewport size for calculating off-screen positions
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var half_screen_width: float = viewport_size.x / 2.0
		var half_screen_height: float = viewport_size.y / 2.0

		# Randomly choose which side to spawn from
		var spawn_from_left: bool = randf() > 0.5

		# Calculate random Y position relative to camera (middle to upper area of screen)
		var random_y_offset: float = randf_range(-spawn_y_variance, spawn_y_variance)
		var spawn_y: float = camera_pos.y - half_screen_height * 0.3 + random_y_offset

		if spawn_from_left:
			# Spawn from left side, off-screen
			enemy.global_position = Vector2(camera_pos.x - half_screen_width - spawn_x_offset, spawn_y)
			enemy.set_direction(1)
		else:
			# Spawn from right side, off-screen
			enemy.global_position = Vector2(camera_pos.x + half_screen_width + spawn_x_offset, spawn_y)
			enemy.set_direction(-1)

		# Set the player reference directly
		enemy.set_player(player)

		# Add to scene and track
		get_tree().root.add_child(enemy)
		active_enemies.append(enemy)

		# Emit signal to let main scene handle the connection
		enemy_spawned.emit(enemy)
