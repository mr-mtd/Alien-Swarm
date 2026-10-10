extends Node3D
## Runs the open map: spawns ever-larger waves of aliens anywhere around the player and handles
## game over / restart.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const DUSKMANE_SCENE := preload("res://scenes/duskmane.tscn")

@export var first_wave_size := 3
@export var wave_growth := 2
## Duskmanes join the waves from this wave on, roughly one for every `duskmane_ratio` aliens.
@export var duskmane_first_wave := 2
@export var duskmane_ratio := 5
## Aliens appear somewhere between these two distances from the player.
@export var spawn_min_distance := 18.0
@export var spawn_max_distance := 40.0
@export var time_between_waves := 2.0

var wave := 0
var kills := 0
var _alive := 0

@onready var _player: Player = $Player
@onready var _enemies: Node3D = $Enemies
@onready var _hud: Hud = $HUD
@onready var _terrain: AlienTerrain = $AlienTerrain


func _ready() -> void:
	_player.health_changed.connect(_hud.set_health)
	_player.died.connect(_on_player_died)
	_hud.set_health(_player.health, _player.max_health)
	_hud.set_kills(kills)
	_next_wave()


func _unhandled_input(event: InputEvent) -> void:
	if _player.is_dead and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _next_wave() -> void:
	wave += 1
	_hud.set_wave(wave)
	var count := first_wave_size + wave_growth * (wave - 1)
	var duskmanes := maxi(floori(count / float(duskmane_ratio)), 1) if wave >= duskmane_first_wave else 0
	for i in count:
		var scene := DUSKMANE_SCENE if i < duskmanes else ENEMY_SCENE
		var enemy: Enemy = scene.instantiate()
		# Position before adding so the body never appears at the origin on top of the player.
		enemy.position = _spawn_point()
		# Waves always hunt the player down, however far away they spawned.
		enemy.detection_range = _terrain.play_radius * 3.0
		_enemies.add_child(enemy)
		enemy.died.connect(_on_enemy_died)
	_alive = count


## A random open spot on the map, a fair distance from the player but close enough to reach them.
func _spawn_point() -> Vector3:
	var center := Vector2(_player.global_position.x, _player.global_position.z)
	var p := Vector2.ZERO
	for attempt in 40:
		var angle := randf() * TAU
		p = center + Vector2(cos(angle), sin(angle)) * randf_range(spawn_min_distance, spawn_max_distance)
		if p.length() < _terrain.play_radius - 4.0 and _terrain.is_open_ground(p.x, p.y, 1.0):
			break
		# Near the edge of the map, fall back to a spot between the player and the middle.
		p = center.move_toward(Vector2.ZERO, spawn_min_distance)
	return Vector3(p.x, _terrain.height_at(p.x, p.y) + 1.0, p.y)


func _on_enemy_died(_enemy: Enemy) -> void:
	kills += 1
	_alive -= 1
	_hud.set_kills(kills)
	if _alive > 0 or _player.is_dead:
		return
	_hud.show_message("Wave %d cleared" % wave, time_between_waves)
	await get_tree().create_timer(time_between_waves).timeout
	if not _player.is_dead:
		_next_wave()


func _on_player_died() -> void:
	_hud.show_message("You were overrun on wave %d\nPress R to restart" % wave)
