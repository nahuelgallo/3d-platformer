class_name State extends Node

## Clase base para estados de una StateMachine.
## Los estados concretos sobreescriben estas funciones virtuales.
## Referencia al state machine padre (se asigna automaticamente en state_machine.gd).

var state_machine: StateMachine


func enter(_params := {}) -> void:
	pass


func exit() -> void:
	pass


func process_physics(_delta: float) -> void:
	pass


func process_input(_event: InputEvent) -> void:
	pass


func process_frame(_delta: float) -> void:
	pass
