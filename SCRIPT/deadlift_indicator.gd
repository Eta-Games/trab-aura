extends Label
## Stato del Deathlift accanto alle barre di ciascun giocatore che lo possiede.

@export var player_id: int = 0

var _player: Player
var _elapsed: float = 0.0


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	add_theme_constant_override("outline_size", 4)
	_find_player()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
	if _player == null:
		visible = false
		return
	var power: Variant = _player.secondary_power
	visible = true
	var supports_deadlift: bool = power != null and power.has_method("is_deadlift") and bool(power.is_deadlift())
	if not supports_deadlift:
		text = "DEATHLIFT NON DISPONIBILE"
		add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		return

	var health_limit: float = float(power.params.get("health_ratio_max", 0.10))
	var aura_required: float = float(power.params.get("aura_ratio_required", 1.0))
	var health_ready: bool = float(_player.current_health) / maxf(float(_player.max_health), 1.0) < health_limit
	var aura_ready: bool = _player.max_stamina > 0.0 and _player.current_stamina >= _player.max_stamina * aura_required
	var available: bool = health_ready and aura_ready and bool(power.can_use())
	if available:
		text = "DEATHLIFT PRONTO"
		_elapsed += delta
		var pulse: float = 0.78 + 0.22 * sin(_elapsed * 6.0)
		add_theme_color_override("font_color", Color(0.45, 1.0, 0.62, pulse))
	else:
		var health_pct: int = roundi(100.0 * float(_player.current_health) / maxf(float(_player.max_health), 1.0))
		var aura_pct: int = roundi(100.0 * _player.current_stamina / maxf(_player.max_stamina, 1.0))
		text = "DEATHLIFT  VITA %d%%  AURA %d%%" % [health_pct, aura_pct]
		add_theme_color_override("font_color", Color(0.95, 0.78, 0.38))


func _find_player() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		_player = _search_player(scene)


func _search_player(node: Node) -> Player:
	for child: Node in node.get_children():
		if child is Player and child.player_id == player_id:
			return child
		var nested: Player = _search_player(child)
		if nested != null:
			return nested
	return null
