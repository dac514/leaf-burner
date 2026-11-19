extends Node

@export var win_count: int = 250

var burning_count: int = 0
var game_time: float = 0.0
var speed_boost_amount: int = 100
var speed_boosts_applied: int = 0
var level: int = 0
var level_start: int = 0  # Score where the current level's progress bar starts
var progress_tween: Tween
var progress_level_up_playing: bool = false
var level_badge_tween: Tween

@onready var burning_leaves_label: Label = %BurningLeaves
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var level_badge: PanelContainer = %LevelBadge
@onready var level_label: Label = %LevelLabel
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
	level += 1
	level_start = win_count
	win_count += win_count
	_show_level()
	_update_progress_bar(true)
	message_bar.set_text("Level " + str(level) + "!")
	message_bar.set_text("Keep going!")
	message_bar.set_text("Burn " + str(win_count) + " leaves to win! ")


## Bar shows progress through the current level, e.g. 250 -> 500 on level 1
func _update_progress_bar(level_up: bool = false) -> void:
	if progress_level_up_playing and not level_up:
		return  # Let the level-up animation finish, it catches up at the end
	if progress_tween:
		progress_tween.kill()
	progress_tween = create_tween()
	if level_up:
		# Top the bar off, then start the new level from empty
		progress_level_up_playing = true
		progress_tween.tween_property(progress_bar, "value", 100.0, 0.15)
		progress_tween.tween_interval(0.35)
		progress_tween.tween_property(progress_bar, "value", 0.0, 0.0)
		progress_tween.tween_callback(_on_level_up_bar_finished)
		return
	var level_size: float = float(win_count - level_start)
	var target_value: float = clamp((burning_count - level_start) / level_size * 100.0, 0.0, 100.0)
	progress_tween.tween_property(progress_bar, "value", target_value, 0.3)


func _on_level_up_bar_finished() -> void:
	progress_level_up_playing = false
	_update_progress_bar()


func _show_level() -> void:
	level_label.text = "LEVEL " + str(level)
	level_badge.visible = true
	level_badge.pivot_offset = level_badge.get_combined_minimum_size() / 2.0
	if level_badge_tween:
		level_badge_tween.kill()
	level_badge.scale = Vector2(1.5, 1.5)
	level_badge.modulate = Color(2.0, 1.6, 1.0)
	level_badge_tween = create_tween().set_parallel()
	level_badge_tween.tween_property(level_badge, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	level_badge_tween.tween_property(level_badge, "modulate", Color.WHITE, 0.8)
