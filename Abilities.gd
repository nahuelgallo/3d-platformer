extends Node

## Sistema de habilidades desbloqueables.
## Base (siempre disponibles): moverse, crouch, salto.
## Desbloqueables: run, dash (suelo + aire), fast_drop, slide (+ slide jump).

var run_unlocked := true  # TODO: cambiar a false cuando haya sistema de progresion
var dash_unlocked := true
var fast_drop_unlocked := false
var slide_unlocked := true
var grappling_hook_unlocked := true


func unlock(ability: String) -> void:
	match ability:
		"run":
			run_unlocked = true
		"dash":
			dash_unlocked = true
		"fast_drop":
			fast_drop_unlocked = true
		"slide":
			slide_unlocked = true
		"grappling_hook":
			grappling_hook_unlocked = true
		_:
			push_warning("Abilities: habilidad desconocida '%s'" % ability)


func unlock_all() -> void:
	run_unlocked = true
	dash_unlocked = true
	fast_drop_unlocked = true
	slide_unlocked = true
	grappling_hook_unlocked = true
