class_name Sfx
extends RefCounted
## Fire-and-forget sound effects. Each call spawns a one-shot player that frees itself when done,
## with a little random pitch so repeated hits don't sound identical. Everything plays on the SFX
## bus (see default_bus_layout.tres), so its overall level can be set in the Audio panel.

const BUS := &"SFX"


## Plays a non-positional sound, for the player's own sounds.
static func play(from: Node, stream: AudioStream, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.08) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.finished.connect(player.queue_free)
	_holder(from).add_child(player)
	player.play()


## Plays a sound in the world at a position, for enemy sounds. It stays put even if the node that
## made it moves or is freed.
static func play_at(
	from: Node, stream: AudioStream, position: Vector3, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.08
) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.unit_size = 8.0
	player.max_distance = 60.0
	player.finished.connect(player.queue_free)
	_holder(from).add_child(player)
	player.global_position = position
	player.play()


static func _holder(from: Node) -> Node:
	var tree := from.get_tree()
	return tree.current_scene if tree.current_scene else tree.root
