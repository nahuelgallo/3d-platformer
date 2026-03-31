extends Node

signal kill_plane_touched
signal flag_reached
signal checkpoint_reached(position: Vector3)
signal aim_started
signal aim_ended
signal hook_fired
signal hook_attached(hook_position: Vector3)
signal hook_released
signal pole_grabbed(pole_position: Vector3)
signal pole_launched(launch_velocity: Vector3)
