# Alien Swarm

A 3D hack and slash game built with [Godot 4](https://godotengine.org) and GDScript.

You're stuck in an arena, and waves of aliens keep coming, with more in each wave. Cut them down with a sword combo, dodge their lunges, and see how many waves you can survive.

## Running the game

1. Install [Godot 4.5](https://godotengine.org/download) or newer (the standard build, not .NET).
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ button) to play.

## Controls

| Action | Input |
| --- | --- |
| Move | W A S D |
| Look | Mouse |
| Attack (press again mid-swing to combo, up to 3 hits) | Left mouse button |
| Dodge roll (brief invulnerability) | Shift |
| Jump | Space |
| Release / recapture mouse | Esc / click |
| Restart after death | R |

## Project layout

```
project.godot       Project settings, input map, physics layer names
scenes/main.tscn    Arena, lighting, HUD; the scene that runs on launch
scenes/player.tscn  Player body, sword, hitbox, third-person camera
scenes/enemy.tscn   Basic alien enemy
scripts/main.gd     Wave spawning, game over and restart
scripts/player.gd   Movement, dodge, combo attacks, health
scripts/enemy.gd    Chase, telegraphed attack, stagger, death
scripts/hud.gd      Health bar, wave and kill counters, messages
```

Physics layers: 1 = world, 2 = player, 3 = enemies.

All visuals are placeholder primitives (capsules and boxes) for now, so they can be swapped for real models and animations later.
