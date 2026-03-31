extends Node

## Sistema de estamina con 4 barras discretas.
## Consumo: barra mas a la derecha con carga suficiente.
## Recarga: barra parcial mas a la izquierda primero, una a la vez.

signal stamina_changed

const MAX_BARS := 4
const RECHARGE_RATE := 0.5    # Por segundo, por barra
const RECHARGE_DELAY := 1.0   # Delay despues de consumir

var bars: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _recharge_cooldown := 0.0


## Intenta consumir `amount` de estamina. Retorna true si habia suficiente.
## Consume de la barra mas a la derecha; si no alcanza, la vacia y saca el resto de la siguiente.
func try_consume(amount: float) -> bool:
	if get_total() < amount:
		return false
	var remaining := amount
	for i in range(MAX_BARS - 1, -1, -1):
		if remaining <= 0.0:
			break
		if bars[i] > 0.0:
			var take := minf(bars[i], remaining)
			bars[i] -= take
			remaining -= take
	_recharge_cooldown = RECHARGE_DELAY
	stamina_changed.emit()
	return true


func get_total() -> float:
	var total := 0.0
	for b in bars:
		total += b
	return total


func _physics_process(delta: float) -> void:
	if _recharge_cooldown > 0.0:
		_recharge_cooldown -= delta
		return

	# Recargar la barra parcial mas a la izquierda
	for i in MAX_BARS:
		if bars[i] < 1.0:
			bars[i] = minf(bars[i] + RECHARGE_RATE * delta, 1.0)
			stamina_changed.emit()
			break  # Solo recargar una barra a la vez
