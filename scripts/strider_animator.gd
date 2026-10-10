class_name StriderAnimator
extends ModelAnimator
## Plays the Emberline Strider's Idle, Walk and Attack animations.
## ModelAnimator does the import-proofing (skin rebinding, clip renaming).


func _init() -> void:
	library_name = &"strider"
	clips = {&"idle": true, &"walk": true, &"attack": false}


func play_idle() -> void:
	play_loop(&"idle")


func play_walk(speed := 1.0) -> void:
	play_loop(&"walk", speed)


## Plays the attack from its first frame, even if an attack is already playing.
func play_attack(speed := 1.0) -> void:
	play_once(&"attack", speed)
