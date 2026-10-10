class_name Duskmane
extends Enemy
## Duskmane: a big club-wielding alien that takes a lot of punishment. It hunts in a cycle: rushes
## the player at a run for a few seconds, then drops to a walk and paces around them at a distance,
## sizing them up, before rushing in again. Clubs the player whenever they are in reach.

enum Mode { RUSH, HOLD }

@export_group("Rush")
@export var run_speed := 5.5
## How long a rush lasts before the duskmane gives up and backs off.
@export var rush_time := 3.0
## Run animation playback speed at full run_speed.
@export var run_anim_speed := 1.5

@export_group("Hold off")
## While holding off, the duskmane paces around the player at roughly this distance.
@export var hold_distance := 7.0
## How long it holds off before the next rush, picked at random between these.
@export var hold_time_min := 4.0
@export var hold_time_max := 6.5
## How far round the player each pacing step goes, in degrees.
@export var pace_angle := 40.0
## Pause between pacing steps, in seconds.
@export var pace_pause := 0.6

@export_group("Toughness")
## Damage it has to take since its last stagger before a hit staggers it again.
@export var stagger_threshold := 60
## Fraction of incoming knockback it actually feels.
@export var knockback_taken := 0.3

var _mode := Mode.RUSH
var _mode_time := 0.0
var _hold_duration := 0.0
var _pace_point := Vector3.ZERO
var _pace_wait := 0.0
var _pace_side := 1.0
var _damage_since_stagger := 0


func _ready() -> void:
	super()
	_pace_side = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_state_time += delta
	_mode_time += delta
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)

	match _state:
		State.DEAD, State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			if _state == State.STAGGER and _state_time >= stagger_time:
				_set_state(State.IDLE)
		State.ATTACK:
			_face_target(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			if not _hit_done and _state_time >= attack_hit_time / attack_anim_speed:
				_hit_done = true
				_hit_target(attack_range + 0.4, attack_damage, attack_knockback)
			if _state_time >= _animator.clip_length(&"attack") / attack_anim_speed:
				_attack_cooldown_left = attack_cooldown
				# After a swing it always backs off before the next rush.
				_start_hold()
				_set_state(State.IDLE)
		_:
			_update_hunt(delta)
	move_and_slide()


func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	_flash()
	if health <= 0:
		velocity = knockback * knockback_taken
		_die()
		return
	_damage_since_stagger += amount
	# It shrugs off light hits and never breaks out of a swing.
	if _state == State.ATTACK or _damage_since_stagger < stagger_threshold:
		return
	_damage_since_stagger = 0
	velocity = knockback * knockback_taken + Vector3.UP * 1.0
	_set_state(State.STAGGER)
	_animator.play_loop(&"idle")
	# Being knocked about makes it come straight back at the player.
	_start_rush()


func _update_hunt(delta: float) -> void:
	if not _can_see_target():
		velocity.x = 0.0
		velocity.z = 0.0
		_set_state(State.IDLE)
		_animator.play_loop(&"idle")
		return
	var offset := _flat_offset_to_target()
	var distance := offset.length()
	if distance <= attack_range and _attack_cooldown_left <= 0.0:
		_start_attack()
		return
	if _mode == Mode.RUSH:
		_update_rush(delta, offset, distance)
	else:
		_update_hold(delta, offset, distance)


func _update_rush(delta: float, offset: Vector3, distance: float) -> void:
	_face_target(delta)
	if _mode_time >= rush_time:
		_start_hold()
		return
	if distance > attack_range * 0.8:
		var direction := offset / distance
		velocity.x = direction.x * run_speed
		velocity.z = direction.z * run_speed
		_set_state(State.CHASE)
		_animator.play_loop(&"run", run_anim_speed)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_state(State.IDLE)
		_animator.play_loop(&"idle")


func _update_hold(delta: float, offset: Vector3, distance: float) -> void:
	if _mode_time >= _hold_duration:
		_start_rush()
		return
	var to_point := _pace_point - global_position
	to_point.y = 0.0
	# Re-plan when it reaches its spot, or when the player has moved and the spot is now off.
	var player_pos := global_position + offset
	var point_off := absf(player_pos.distance_to(Vector3(_pace_point.x, player_pos.y, _pace_point.z)) - hold_distance)
	if to_point.length() < 0.5 or point_off > hold_distance * 0.5:
		velocity.x = 0.0
		velocity.z = 0.0
		if _pace_wait <= 0.0:
			_pace_wait = pace_pause
		_pace_wait -= delta
		_face_target(delta)
		_set_state(State.IDLE)
		_animator.play_loop(&"idle")
		if _pace_wait <= 0.0:
			_pick_pace_point(offset, distance)
		return
	# Walk to the spot, looking where it is going.
	var direction := to_point.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-direction.x, -direction.z), turn_speed * delta)
	_set_state(State.CHASE)
	_animator.play_loop(&"walk", walk_anim_speed)


func _start_rush() -> void:
	_mode = Mode.RUSH
	_mode_time = 0.0


func _start_hold() -> void:
	_mode = Mode.HOLD
	_mode_time = 0.0
	_hold_duration = randf_range(hold_time_min, hold_time_max)
	_pace_wait = 0.0
	# Start by stepping back out to the holding distance.
	if _can_see_target():
		var offset := _flat_offset_to_target()
		_pick_pace_point(offset, offset.length())


## Picks the next spot to pace to: on the circle round the player, a step further round.
func _pick_pace_point(offset: Vector3, distance: float) -> void:
	var from_player := -offset / distance if distance > 0.01 else Vector3.FORWARD
	# Usually keep circling the same way, sometimes turn back.
	if randf() < 0.3:
		_pace_side = -_pace_side
	var step := deg_to_rad(pace_angle * randf_range(0.6, 1.2)) * _pace_side
	var player_pos := global_position + offset
	_pace_point = player_pos + from_player.rotated(Vector3.UP, step) * hold_distance
	_pace_point.y = global_position.y
