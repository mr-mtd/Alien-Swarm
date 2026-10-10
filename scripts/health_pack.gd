class_name HealthPack
extends Area3D
## A glowing cross dropped by dead aliens. Walking into it restores health (never past the
## player's max, and it stays put while they are already at full health). It bobs and spins so it
## is easy to spot against the lava, blinks for its last few seconds and then fades away.

@export var heal_amount := 25
## Seconds before an uncollected pack disappears.
@export var lifetime := 20.0
## It blinks for this many seconds before it disappears.
@export var blink_time := 4.0
@export var bob_height := 0.15
@export var bob_speed := 2.5
## Degrees per second.
@export var spin_speed := 90.0
@export var glow_color := Color(0.35, 1.0, 0.75)

var _age := 0.0
var _collected := false

@onready var _model: Node3D = $Model
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 1.0, 0.92)
	material.emission_enabled = true
	material.emission = glow_color
	material.emission_energy_multiplier = 2.5
	for bar: MeshInstance3D in _model.get_children():
		bar.material_override = material
	_light.light_color = glow_color
	# Pop out of the body it dropped from.
	_model.scale = Vector3.ZERO
	create_tween().tween_property(_model, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	_model.position.y = sin(_age * bob_speed) * bob_height
	_model.rotate_y(deg_to_rad(spin_speed) * delta)
	var time_left := lifetime - _age
	if time_left <= 0.0:
		queue_free()
	elif time_left < blink_time:
		# Blink faster as it runs out.
		var rate := lerpf(4.0, 12.0, 1.0 - time_left / blink_time)
		var on := fmod(_age * rate, 1.0) < 0.6
		_model.visible = on
		_light.visible = on


func _physics_process(_delta: float) -> void:
	if _collected:
		return
	# Polled rather than body_entered so a player standing on it at full health still picks it
	# up once they get hurt.
	for body in get_overlapping_bodies():
		if body is Player and _try_heal(body):
			return


func _try_heal(player: Player) -> bool:
	if player.is_dead or player.health >= player.max_health:
		return false
	var healed := player.heal(heal_amount)
	_collected = true
	# A collected pack no longer counts toward the cap on packs lying around.
	remove_from_group("health_packs")
	_model.visible = true
	_light.visible = true
	_show_heal_label(healed)
	var tween := create_tween().set_parallel()
	tween.tween_property(_model, "scale", Vector3.ONE * 1.8, 0.25)
	tween.tween_property(_model, "position:y", _model.position.y + 0.8, 0.25)
	tween.tween_property(_light, "light_energy", 0.0, 0.25)
	tween.chain().tween_callback(_model.hide)
	return true


## A "+25" that floats up from the pack and fades.
func _show_heal_label(amount: int) -> void:
	var label := Label3D.new()
	label.text = "+%d" % amount
	label.modulate = glow_color.lightened(0.3)
	label.outline_modulate = Color(0.0, 0.15, 0.1)
	label.font_size = 64
	label.outline_size = 12
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3.UP * 0.8
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", 2.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(queue_free)
