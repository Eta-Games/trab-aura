extends "res://SCRIPT/powers/fighter_power.gd"
## Deathlift di Perux: Il lenzuolino.

var _busy := false
var _overlay: CanvasLayer
var _cloth: Polygon2D


func default_params() -> Dictionary:
	return {
		"cooldown": 9999.0,
		"health_ratio_max": 0.10,
		"aura_ratio_required": 1.0,
		"damage": 8,
		"dot_interval": 2.0,
		"dot_damage": 2,
		"text_seconds": 1.4,
		"duration": 9999.0,
	}


func _on_setup() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "LenzuolinoOverlay"
	_overlay.layer = 10
	add_child(_overlay)


func can_use() -> bool:
	return player != null and not _busy and player.max_health > 0 \
		and float(player.current_health) / player.max_health < float(params["health_ratio_max"]) \
		and player.current_stamina >= player.max_stamina * float(params["aura_ratio_required"]) \
		and cooldown_left <= 0.0


func is_busy() -> bool:
	return _busy


func is_deadlift() -> bool:
	return true


func use() -> void:
	var target := _find_opponent()
	if target == null or not can_use():
		return
	super.use()
	_spend_stamina(player.current_stamina)
	_busy = true
	var locked: Array[Player] = [player, target]
	for fighter in locked:
		fighter.combat_locked = true
		fighter.velocity = Vector2.ZERO
		fighter.is_blocking = false
	player._set_facing(target.global_position.x < player.global_position.x)
	target._set_facing(player.global_position.x < target.global_position.x)
	_show_letterbox()
	_show_title()
	await player.get_tree().create_timer(float(params["text_seconds"])).timeout
	if not is_instance_valid(target):
		_unlock(locked)
		_busy = false
		return
	var before := target.current_health
	target.combat_locked = false
	target.hurtbox.take_damage(int(params["damage"]), player)
	if target.current_health < before:
		_apply_sheet(target)
		_apply_dot(target)
	_unlock(locked)
	_busy = false


func _apply_sheet(target: Player) -> void:
	# Il lenzuolo vola fino al bersaglio e poi resta avvolto sulla testa.
	_cloth = Polygon2D.new()
	_cloth.name = "IlLenzuolino"
	_cloth.color = Color(0.92, 0.91, 0.82, 0.96)
	_cloth.polygon = PackedVector2Array([Vector2(-28, -95), Vector2(28, -95), Vector2(31, -43), Vector2(17, -25), Vector2(0, -38), Vector2(-18, -25), Vector2(-31, -43)])
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(_cloth)
	_cloth.global_position = player.global_position + Vector2(0, -player.get_visual_height() * 0.5)
	var head_position: Vector2 = target.global_position + Vector2(0, -target.get_visual_height() * 0.52)
	var flight := _cloth.create_tween()
	flight.tween_property(_cloth, "global_position", head_position, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	flight.tween_callback(func():
		if is_instance_valid(_cloth) and is_instance_valid(target):
			var cloth_position := _cloth.global_position
			_cloth.reparent(target)
			_cloth.position = cloth_position - target.global_position
	)
	target.died.connect(func(_dead_player):
		if is_instance_valid(_cloth):
			_cloth.queue_free()
	)
	_blink_perux(target)


func _apply_dot(target: Player) -> void:
	var interval := maxf(float(params["dot_interval"]), 0.1)
	while is_instance_valid(target) and not target.is_dead:
		await get_tree().create_timer(interval).timeout
		if is_instance_valid(target) and not target.is_dead:
			target.hurtbox.take_damage(int(params["dot_damage"]), player)


func _blink_perux(target: Player) -> void:
	var original_visible: bool = player.current_sprite.visible
	while is_instance_valid(target) and not target.is_dead:
		player.current_sprite.visible = false
		await get_tree().create_timer(0.18).timeout
		if not is_instance_valid(target) or target.is_dead:
			break
		player.current_sprite.visible = original_visible
		await get_tree().create_timer(0.32).timeout
	player.current_sprite.visible = original_visible


func _show_letterbox() -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = bar.anchor_top
		bar.offset_bottom = 54.0 if top else 0.0
		bar.offset_top = 0.0 if top else -54.0
		_overlay.add_child(bar)
	get_tree().create_timer(float(params["text_seconds"])).timeout.connect(func():
		for child in _overlay.get_children():
			child.queue_free()
	)


func _show_title() -> void:
	var label := Label.new()
	label.text = "IL LENZUOLINO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 46)
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1))
	label.add_theme_constant_override("outline_size", 10)
	_overlay.add_child(label)


func _unlock(fighters: Array[Player]) -> void:
	for fighter in fighters:
		if is_instance_valid(fighter) and not fighter.is_dead:
			fighter.combat_locked = false
	_busy = false


func _find_opponent() -> Player:
	for node in player.get_parent().get_children():
		if node is Player and node != player and not node.is_dead and node.current_health > 0:
			return node
	return null
