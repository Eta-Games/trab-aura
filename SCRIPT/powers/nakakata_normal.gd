extends "res://SCRIPT/powers/fighter_power.gd"
## Attacco normale sul tasto secondario, disponibile fuori dalla soglia deathlift.

func default_params() -> Dictionary:
	return {"cooldown": 5.0, "stamina_min": 0.0, "stamina_cost": 0.0}


func use() -> void:
	if player == null or not player.is_on_floor() or player.isAttacking:
		return
	super.use()
	player.attack()
