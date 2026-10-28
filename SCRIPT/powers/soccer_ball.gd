extends Node2D

var direction := 1.0
var speed := 1050.0
var radius := 30.0
var target: Player
var owner_player: Player
var damage := 35
var _age := 0.0


func setup(heading: float, velocity: float, size: float, victim: Player, owner: Player, hit_damage: int) -> void:
	direction = heading
	speed = velocity
	radius = size
	target = victim
	owner_player = owner
	damage = hit_damage


func _process(delta: float) -> void:
	_age += delta
	global_position.x += direction * speed * delta
	rotation += direction * delta * 12.0
	queue_redraw()
	if is_instance_valid(target) and not target.is_dead and target.current_health > 0:
		if global_position.distance_to(target.hurtbox.global_position) <= radius + 28.0:
			target.hurtbox.take_damage(damage, owner_player)
			queue_free()
			return
	if _age > 2.0 or absf(global_position.x - owner_player.global_position.x) > 2400.0:
		queue_free()


func _draw() -> void:
	# Palla leggibile anche in volo: pannelli esagonali neri su base bianca.
	draw_circle(Vector2.ZERO, radius, Color(0.96, 0.96, 0.93))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.12, 0.12, 0.12), 2.0)
	var pentagon := PackedVector2Array()
	for i in range(5):
		var angle := -PI / 2.0 + TAU * float(i) / 5.0
		pentagon.append(Vector2(cos(angle), sin(angle)) * radius * 0.34)
	draw_colored_polygon(pentagon, Color(0.08, 0.08, 0.08))
	for i in range(5):
		var angle := -PI / 2.0 + TAU * float(i) / 5.0
		var center := Vector2(cos(angle), sin(angle)) * radius * 0.72
		var patch := PackedVector2Array()
		for j in range(5):
			var a := angle + PI / 5.0 + TAU * float(j) / 5.0
			patch.append(center + Vector2(cos(a), sin(a)) * radius * 0.19)
		draw_colored_polygon(patch, Color(0.10, 0.10, 0.10))
