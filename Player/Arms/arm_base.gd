class_name ArmBase extends Node3D

# Clase base para todos los brazos. Cada brazo extiende esto
# e implementa sus propias acciones.

signal arm_state_changed(new_state: String)

var player: CharacterBody3D


func _setup(p: CharacterBody3D) -> void:
	player = p


func primary_action() -> void:
	pass


func secondary_action() -> void:
	pass


func release_action() -> void:
	pass
