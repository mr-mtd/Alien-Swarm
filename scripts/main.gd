extends Node3D
## Runs the arena: spawns ever-larger waves of aliens and handles game over / restart.

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

@export var first_wave_size := 3
@export var wave_growth := 2
@export var spawn_radius := 16.0
@export var time_between_waves := 2.0

var wave := 0
var kills := 0
var _alive := 0

@onready var _player: Player = $Player
@onready var _enemies: Node3D = $Enemies
@onready var _hud: Hud = $HUD


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
	for i in count:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		# Position before adding so the body never appears at the origin on top of the player.
		var angle := randf() * TAU
		enemy.position = Vector3(cos(angle), 0.0, sin(angle)) * spawn_radius + Vector3.UP
		_enemies.add_child(enemy)
		enemy.died.connect(_on_enemy_died)
	_alive = count


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
