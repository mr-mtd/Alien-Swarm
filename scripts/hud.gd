class_name Hud
extends CanvasLayer

var _message_id := 0

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _wave_label: Label = %WaveLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _message_label: Label = %MessageLabel


func set_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func set_wave(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave


func set_kills(kills: int) -> void:
	_kills_label.text = "Kills: %d" % kills


## Shows a centered message. A duration of 0 keeps it up until the next message.
func show_message(text: String, duration := 0.0) -> void:
	_message_id += 1
	var id := _message_id
	_message_label.text = text
	_message_label.visible = true
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if id == _message_id:
			_message_label.visible = false
