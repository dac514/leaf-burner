extends Node

@export var win_count: int = 250

var burning_count: int = 0
var game_time: float = 0.0
var speed_boost_amount: int = 100
var speed_boosts_applied: int = 0

@onready var burning_leaves_label: Label = %BurningLeaves
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var left_furnace_area: Area2D = %LeftFurnaceArea
@onready var right_furnace_area: Area2D = %RightFurnaceArea
@onready var leaf_spawner: LeafSpawner = $LeafSpawner
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var player: Player = $Player
@onready var message_bar: MessageBar = %MessageBar


func _ready() -> void:
	left_furnace_area.body_entered.connect(_on_furnace_area_body_entered)
	right_furnace_area.body_entered.connect(_on_furnace_area_body_entered)
	leaf_spawner.leaf_spawned.connect(_on_leaf_spawned)
	enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)
	# The burning barrels mark the edge of the playable area
	leaf_spawner.left_bound_x = (left_furnace_area.get_parent() as Node2D).global_position.x
	leaf_spawner.right_bound_x = (right_furnace_area.get_parent() as Node2D).global_position.x

	await get_tree().create_timer(3.0).timeout
	message_bar.set_text("Burn " + str(win_count) + " leaves to win! ")


func _process(delta: float) -> void:
	game_time += delta
	# Check for speed increases every 30 seconds, max 10 boosts
	var expected_boosts: int = int(game_time / 30.0)
	if expected_boosts > speed_boosts_applied and speed_boosts_applied <= 10:
		player.max_speed += speed_boost_amount
		speed_boosts_applied = expected_boosts
		message_bar.set_text("Speed boost +" + str(speed_boosts_applied))


func _on_furnace_area_body_entered(body: Node2D) -> void:
	if body is Leaf:
		var leaf: Leaf = body as Leaf
		leaf.try_burn()


func _on_leaf_spawned(leaf: Leaf) -> void:
	# Connect each new leaf's hit signal to our handler
	leaf.leaf_burned.connect(_on_leaf_burned)


func _on_enemy_hit_player(_enemy: Enemy) -> void:
	# Reduce burning leaves count by 100
	burning_count = max(0, burning_count - 100)
	burning_leaves_label.text = str(burning_count)
	_update_progress_bar()
	message_bar.set_text("Hit by enemy! Lost 100 points!")


func _on_enemy_spawned(enemy: Enemy) -> void:
	# Connect each new enemy's hit signal to our handler
	enemy.enemy_hit_player.connect(_on_enemy_hit_player)


func _on_leaf_burned(_leaf: Leaf) -> void:
	burning_count += 1
	burning_leaves_label.text = str(burning_count)
	_update_progress_bar()
	# Check win condition
	if burning_count >= win_count:
		_on_game_won()


func _on_game_won() -> void:
	var total_seconds: int = int(game_time)
	var minutes: int = int(total_seconds / 60.0)
	var seconds: int = total_seconds % 60
	var time_string: String

	if minutes > 0:
		time_string = "%d minutes and %d seconds" % [minutes, seconds]
	else:
		time_string = "%d seconds" % seconds

	message_bar.message_queue = []
	message_bar.set_text("You win!")
	message_bar.set_text(str(win_count) + " leaves in " + time_string)
	win_count += win_count
	_update_progress_bar()
	message_bar.set_text("Keep going!")
	message_bar.set_text("Burn " + str(win_count) + " leaves to win! ")


func _update_progress_bar() -> void:
	var target_value: float = clamp((float(burning_count) / win_count) * 100.0, 0.0, 100.0)
	var tween := get_tree().create_tween()
	tween.tween_property(progress_bar, "value", target_value, 0.3)
