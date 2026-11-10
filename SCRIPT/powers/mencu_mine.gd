extends "res://SCRIPT/powers/fighter_power.gd"

const PROJECTILE_SCRIPT := preload("res://SCRIPT/powers/mencu_mine_projectile.gd")

var _burger_texture: Texture2D
var _mine_armed: bool = false
var _warning_active: bool = false
var _mine_position: Vector2 = Vector2.ZERO
var _mine_area: Area2D


func default_params() -> Dictionary:
	return {
		"cooldown": 5.0,
		"stamina_min": 60.0,
		"stamina_cost": 60.0,
		"charge_time": 1.0,
		"mine_texture": "res://sprite/Player/IlMencu/Secondary/burger_nobg.png",
		"mine_trigger_radius": 50.0,
		"warning_time": 1.5,
		"projectile_count": 12,
		"projectile_damage": 35,
		"projectile_speed": 520.0,
		"projectile_lifetime": 1.5,
		"projectile_scale": 0.045,
		"projectile_hit_radius": 12.0,
	}


func _on_setup() -> void:
	_burger_texture = load(str(params["mine_texture"])) as Texture2D
	if _burger_texture == null:
		push_warning("Mencu mine: immagine hamburger non trovata: %s" % params["mine_texture"])


func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return float(params["charge_time"])


func use() -> void:
	# La pressione breve non piazza la mina: occorre tenere premuto 1 secondo.
	pass


func is_busy() -> bool:
	# A delayed trap does not lock its owner's movement.
	return false


func can_use() -> bool:
	return cooldown_left <= 0.0 and not _mine_armed and not _warning_active \
		and _has_stamina(float(params["stamina_min"]))


func start_charge() -> bool:
	if _mine_armed or _warning_active or _burger_texture == null:
		return false
	var opponent: Player = _find_opponent()
	if opponent == null or not _has_stamina(float(params["stamina_cost"])):
		return false
	_mine_position = _choose_mine_position(opponent)
	_mine_armed = true
	_create_mine_area()
	_spend_stamina(float(params["stamina_cost"]))
	cooldown_left = float(params["cooldown"])
	return true


func release_charge() -> void:
	# La mina resta armata anche dopo il rilascio del tasto.
	pass


func _update_power(_delta: float) -> void:
	pass


func _choose_mine_position(opponent: Player) -> Vector2:
	# Put the mine on the shared ground corridor between both current positions.
	# This keeps it on the playable floor instead of relying on TileMap bounds.
	var owner_feet: Vector2 = _get_feet_position(player)
	var opponent_feet: Vector2 = _get_feet_position(opponent)
	var left: float = minf(player.global_position.x, opponent.global_position.x)
	var right: float = maxf(player.global_position.x, opponent.global_position.x)
	var span: float = right - left
	var safe_margin: float = maxf(float(params["mine_trigger_radius"]) + 30.0, 70.0)
	var margin: float = minf(safe_margin, span * 0.35)
	var x: float = randf_range(left + margin, right - margin) if span > 1.0 else left
	var ratio: float = (x - left) / span if span > 1.0 else 0.5
	var floor_y: float = lerpf(owner_feet.y, opponent_feet.y, ratio)
	var point: Vector2 = Vector2(x, floor_y - 8.0)
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		Vector2(x, floor_y - 300.0), Vector2(x, floor_y + 300.0)
	)
	query.exclude = [player.get_rid(), opponent.get_rid()]
	query.collide_with_areas = false
	var hit: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit["normal"] as Vector2).y <= -0.55 \
			and absf((hit["position"] as Vector2).y - floor_y) <= 120.0:
		point.y = (hit["position"] as Vector2).y - 8.0
	return point


func _create_mine_area() -> void:
	_mine_area = Area2D.new()
	_mine_area.name = "MencuHiddenMine"
	_mine_area.collision_layer = 0
	_mine_area.collision_mask = 0x7fffffff
	_mine_area.monitoring = true
	_mine_area.monitorable = false
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = float(params["mine_trigger_radius"])
	shape_node.shape = circle
	_mine_area.add_child(shape_node)
	player.get_tree().current_scene.add_child(_mine_area)
	_mine_area.global_position = _mine_position
	_mine_area.body_entered.connect(_on_mine_body_entered)


func _on_mine_body_entered(body: Node2D) -> void:
	if not _mine_armed or _warning_active or not (body is Player) or body == player:
		return
	var target: Player = body as Player
	if target.is_dead or target.current_health <= 0:
		return
	_mine_armed = false
	_warning_active = true
	if is_instance_valid(_mine_area):
		_mine_area.queue_free()
	_warning_then_burst(target)


func _get_feet_position(fighter: Player) -> Vector2:
	var body_shape: CollisionShape2D = fighter.get_node_or_null("collision") as CollisionShape2D
	if body_shape != null and body_shape.shape != null:
		var shape_bounds: Rect2 = body_shape.shape.get_rect()
		return body_shape.to_global(Vector2(0.0, shape_bounds.end.y))
	return fighter.global_position + Vector2(0.0, fighter.get_visual_height() * 0.5)


func _find_opponent() -> Player:
	for candidate: Node in player.get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			return candidate
	return null


func _warning_then_burst(target: Player) -> void:
	var scene: Node = player.get_tree().current_scene
	var overlay: CanvasLayer = _create_warning_overlay(scene)
	var blink: Tween
	for edge: ColorRect in overlay.get_children():
		blink = player.get_tree().create_tween()
		blink.set_loops(5)
		blink.tween_property(edge, "modulate:a", 0.9, 0.15)
		blink.tween_property(edge, "modulate:a", 0.0, 0.15)
	if blink != null:
		await blink.finished
	else:
		await player.get_tree().create_timer(float(params["warning_time"])).timeout
	if is_instance_valid(overlay):
		overlay.queue_free()
	if is_instance_valid(target) and target.current_health > 0:
		_spawn_burst(scene, target)
	_warning_active = false


func _create_warning_overlay(scene: Node) -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 40
	scene.add_child(layer)
	var top: ColorRect = _make_edge()
	top.anchor_right = 1.0
	top.offset_bottom = 32.0
	layer.add_child(top)
	var bottom: ColorRect = _make_edge()
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -32.0
	layer.add_child(bottom)
	var left: ColorRect = _make_edge()
	left.anchor_bottom = 1.0
	left.offset_right = 32.0
	layer.add_child(left)
	var right: ColorRect = _make_edge()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -32.0
	layer.add_child(right)
	return layer


func _make_edge() -> ColorRect:
	var edge: ColorRect = ColorRect.new()
	edge.color = Color.RED
	edge.modulate.a = 0.0
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return edge


func _spawn_burst(scene: Node, target: Player) -> void:
	var count: int = maxi(int(params["projectile_count"]), 1)
	for index in range(count):
		var angle: float = TAU * float(index) / float(count)
		var direction: Vector2 = Vector2.RIGHT.rotated(angle)
		var shot: MencuMineProjectile = PROJECTILE_SCRIPT.new()
		scene.add_child(shot)
		shot.setup(_burger_texture, _mine_position, direction, self, target)

