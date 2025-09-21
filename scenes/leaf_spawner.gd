class_name LeafSpawner extends Node2D

signal leaf_spawned(leaf: Leaf)

@export var leaf_scene: PackedScene = preload("res://scenes/leaf.tscn")
@export var spawn_interval: float = 0.1  # 10 leaves per second

var active_leaves: Array[Leaf] = []
var left_wall_x: float = -911.25
var right_wall_x: float = 2447.5
var spawn_height: float = -100
var time_since_last_spawn: float = 0.0


func _process(delta: float) -> void:
	# Clean up invalid leaf references
	active_leaves = active_leaves.filter(func(leaf: Leaf) -> bool: return is_instance_valid(leaf))

	time_since_last_spawn += delta
	while time_since_last_spawn >= spawn_interval:
		spawn_leaf()
		time_since_last_spawn -= spawn_interval


func spawn_leaf() -> void:
	if leaf_scene:
		var leaf: Leaf = leaf_scene.instantiate()
		var random_x := randf_range(left_wall_x, right_wall_x)
		leaf.global_position = Vector2(random_x, global_position.y + spawn_height)
		leaf.spawner = self
		get_tree().root.add_child(leaf)
		active_leaves.append(leaf)

		# Emit signal to let main scene handle the connection
		leaf_spawned.emit(leaf)


func remove_leaf(leaf: Leaf) -> void:
	active_leaves.erase(leaf)
