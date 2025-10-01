# Leaf Burner - Godot Game Development Guide

This is a 2D arcade-style Godot game built for Godot Wild Jam #85. Players collect falling leaves and burn them in barrels while avoiding enemies.

## Architecture Overview

The game follows a signal-driven architecture with clear separation of concerns:

- **Main Scene** (`scenes/main.gd`): Central controller that coordinates all game systems via signals
- **Spawners** (`leaf_spawner.gd`, `enemy_spawner.gd`): Manage object lifecycle and emit spawned object signals
- **Player** (`player.gd`): Multi-state character controller with leaf collection and throwing mechanics
- **Game Objects** (`leaf.gd`, `enemy.gd`): State-driven entities with their own lifecycle management

## Signal-Based Communication Pattern

All major interactions use Godot signals for loose coupling:

```gdscript
# Spawners emit when objects are created
leaf_spawner.leaf_spawned.connect(_on_leaf_spawned)
enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)

# Game objects emit for state changes
leaf.leaf_burned.connect(_on_leaf_burned)
enemy.enemy_hit_player.connect(_on_enemy_hit_player)
```

**Key Pattern**: Main scene connects to spawner signals, then dynamically connects to individual object signals as they're created.

## Game State Management

- **Leaf States**: `FALLING` → `FOLLOWING` → `DROPPED` → burned (with collision layer changes per state)
- **Player Collection**: Dynamic array of collected leaves with visual following behavior
- **Progressive Difficulty**: Enemy spawn rate and player speed increase over time
- **Win Condition**: Incremental (250 → 500 → 750 leaves) with game continuation

## Collision System

Uses Godot's physics layers for precise interaction control:
- Layer 2: Leaves (disabled when following player)
- Layer 4: Floors (leaves ignore when following)
- Layer 5: Furnaces aka barrels (for burning detection)

## Development Conventions

- **Class Names**: All major game objects use `class_name` declarations for type safety
- **Node References**: Use `@onready` with unique names (`%NodeName`) for cross-scene references
- **Export Variables**: Expose key parameters for designer tuning (`@export var win_count: int = 250`)
- **Cleanup Pattern**: Manual object cleanup with spawner tracking for memory management

## File Organization

- `scenes/`: Contains all `.tscn` scene files and their corresponding `.gd` scripts
- `assets/`: Sprites and textures (note the `.import` files for each asset)
- Script naming matches scene names exactly (`player.tscn` ↔ `player.gd`)

## Testing & Debugging

Game uses `message_bar.gd` for runtime feedback. When debugging:
- Check signal connections in Main scene `_ready()`
- Verify collision layers match the state management logic
- Monitor spawner cleanup in `_process()` methods

## Performance Considerations

- Spawners actively clean up invalid object references each frame
- Leaf collection uses filtered arrays to handle destroyed objects
- Background processes (spawning) use time-based intervals, not frame-based