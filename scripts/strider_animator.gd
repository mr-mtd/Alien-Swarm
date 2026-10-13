class_name StriderAnimator
extends ModelAnimator
## Plays the Emberline Strider's Idle, Walk, Attack and dodge-roll animations.
## ModelAnimator does the import-proofing (skin rebinding, clip renaming).

## Roll directions, relative to the way the Strider is facing.
const ROLL_DIRECTIONS: Array[StringName] = [&"forward", &"back", &"left", &"right"]


func _init() -> void:
	library_name = &"strider"
	clips = {
		&"idle": true,
		&"walk": true,
		&"attack": false,
		&"roll_forward": false,
		&"roll_back": false,
		&"roll_left": false,
		&"roll_right": false,
	}


func play_idle() -> void:
	play_loop(&"idle")


func play_walk(speed := 1.0) -> void:
	play_loop(&"walk", speed)


## Plays the attack from its first frame, even if an attack is already playing.
func play_attack(speed := 1.0) -> void:
	play_once(&"attack", speed)


## Plays a tuck-and-roll in `direction` (one of ROLL_DIRECTIONS) so that it lasts `duration` seconds.
## The roll stays in place: whoever calls this moves the body.
func play_roll(direction: StringName, duration: float) -> void:
	var clip := StringName("roll_" + direction)
	var length := clip_length(clip)
	if length <= 0.0:
		return
	play_once(clip, length / maxf(duration, 0.05))
