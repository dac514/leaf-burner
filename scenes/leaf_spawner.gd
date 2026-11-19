class_name LeafSpawner extends Node2D

signal leaf_spawned(leaf: Leaf)

@export var leaf_scene: PackedScene = preload("res://scenes/leaf.tscn")
@export var spawn_interval: float = 0.1  # 10 leaves per second
## Seconds a leaf may rest outside the barrels before it is removed
@export var out_of_bounds_lifetime: float = 60.0
## Most leaves alive at once. At the cap the oldest resting leaf fades out as each new one
## spawns, so leaves keep falling but the physics load stops growing (provisional, tune on device)
@export var max_active_leaves: int = 350

var active_leaves: Array[Leaf] = []
var left_wall_x: float = -911.25
var right_wall_x: float = 2447.5
var spawn_height: float = -100
var time_since_last_spawn: float = 0.0
# Leaves beyond these x positions (the burning barrels) can't be reached by the player
var left_bound_x: float = -INF
var right_bound_x: float = INF
var time_since_bounds_check: float = 0.0


func _process(delta: float) -> void:
	time_since_last_spawn += delta
	while time_since_last_spawn >= spawn_interval:
		spawn_leaf()
		time_since_last_spawn -= spawn_interval

	# Once per second is plenty for cleanup and keeps per-frame cost low
	time_since_bounds_check += delta
	if time_since_bounds_check >= 1.0:
		_despawn_out_of_bounds_leaves(time_since_bounds_check)
		time_since_bounds_check = 0.0


func spawn_leaf() -> void:
	if active_leaves.size() >= max_active_leaves:
		_recycle_oldest_leaf()
	if leaf_scene:
		var leaf: Leaf = leaf_scene.instantiate()
		var random_x := randf_range(left_wall_x, right_wall_x)
		leaf.global_position = Vector2(random_x, global_position.y + spawn_height)
		leaf.spawner = self
		get_tree().root.add_child(leaf)
		active_leaves.append(leaf)

		# Emit signal to let main scene handle the connection
		leaf_spawned.emit(leaf)


## active_leaves is in spawn order, so the first leaf that's just lying around is the oldest
func _recycle_oldest_leaf() -> void:
	for leaf in active_leaves:
		if not is_instance_valid(leaf) or leaf.is_removing or leaf.current_state == Leaf.State.FOLLOWING:
			continue
		if leaf.is_freshly_thrown():
			continue
		leaf.despawn()
		return


func remove_leaf(leaf: Leaf) -> void:
	active_leaves.erase(leaf)


func _despawn_out_of_bounds_leaves(elapsed: float) -> void:
	# Leaves normally remove themselves via remove_leaf(); this just drops any stray freed ones
	var still_alive: Array[Leaf] = []
	for i in range(active_leaves.size()):
		var item: Variant = active_leaves[i]
		if is_instance_valid(item):
			still_alive.append(item as Leaf)
	active_leaves = still_alive
	for leaf in active_leaves:
		if leaf.is_removing or leaf.current_state == Leaf.State.FOLLOWING:
			leaf.out_of_bounds_time = 0.0
			continue
		var x := leaf.global_position.x
		if x < left_bound_x or x > right_bound_x:
			leaf.out_of_bounds_time += elapsed
			if leaf.out_of_bounds_time >= out_of_bounds_lifetime:
				leaf.despawn()
		else:
			leaf.out_of_bounds_time = 0.0
