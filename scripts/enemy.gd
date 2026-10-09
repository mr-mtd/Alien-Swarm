class_name Enemy
extends CharacterBody3D
## Basic alien: chases the player, telegraphs a lunge, and staggers when hit.

signal died(enemy: Enemy)

@export var max_health := 60
@export var move_speed := 3.5
@export var turn_speed := 10.0
@export var detection_range := 30.0
@export var attack_range := 1.8
@export var attack_damage := 10
@export var attack_windup := 0.45
@export var attack_cooldown := 1.2
@export var stagger_time := 0.35

var health := 0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _target: Player
var _cooldown_left := 0.0
var _stagger_left := 0.0
var _attacking := false
var _dead := false
var _hurt_material := StandardMaterial3D.new()

@onready var _model: Node3D = $Model
@onready var _body_mesh: MeshInstance3D = $Model/Body


func _ready() -> void:
	health = max_health
	_target = get_tree().get_first_node_in_group("player") as Player
	_hurt_material.albedo_color = Color(1, 1, 1)
	_hurt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_stagger_left = maxf(_stagger_left - delta, 0.0)

	if _stagger_left > 0.0:
		# Slide out the knockback.
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	var chase := Vector3.ZERO
	if _can_see_target():
		var to_target := _target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > 0.01:
			var direction := to_target / distance
			_model.rotation.y = lerp_angle(
				_model.rotation.y, atan2(-direction.x, -direction.z), turn_speed * delta
			)
			if not _attacking:
				if distance > attack_range * 0.8:
					chase = direction * move_speed
				elif _cooldown_left <= 0.0:
					_attack()
	velocity.x = chase.x
	velocity.z = chase.z
	move_and_slide()


func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	health -= amount
	velocity = knockback + Vector3.UP * 2.0
	_stagger_left = stagger_time
	_flash()
	if health <= 0:
		_die()


func _attack() -> void:
	_attacking = true
	# Telegraph: squash down before lunging so the player can react.
	var windup := create_tween()
	windup.tween_property(_model, "scale", Vector3(1.2, 0.8, 1.2), attack_windup)
	await windup.finished
	# Getting hit during the windup cancels the attack.
	if not _dead and _stagger_left <= 0.0 and _can_see_target():
		var offset := _target.global_position - global_position
		offset.y = 0.0
		if offset.length() <= attack_range:
			_target.take_damage(attack_damage, offset.normalized() * 4.0)
	_model.scale = Vector3.ONE
	_cooldown_left = attack_cooldown
	_attacking = false


func _can_see_target() -> bool:
	return (
		not _dead
		and is_instance_valid(_target)
		and not _target.is_dead
		and global_position.distance_to(_target.global_position) <= detection_range
	)


func _die() -> void:
	_dead = true
	collision_layer = 0
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)


func _flash() -> void:
	_body_mesh.material_override = _hurt_material
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(_body_mesh):
		_body_mesh.material_override = null
