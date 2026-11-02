extends Node2D

@onready var label: Label = $Label
@onready var cursore: ColorRect = $Cursore

@onready var anteprima_p1: Sprite2D = $AnteprimaP1
@onready var anteprima_p2: Sprite2D = $AnteprimaP2

@onready var bisio_btn: Button = $bisio
@onready var tommaso_btn: Button = $tommaso
@onready var nakakata_btn: Button = $nakakata
@onready var andrix_btn: Button = $andrix
@onready var mencu_btn: Button = $mencu
@onready var perucx_btn: Button = $perucx

# 0 = trab, 1 = iacopo, 2 = naka
const PREVIEW_TEXTURES := {
	0: preload("res://sprite/Player/proppick/WND_trab_bigprop.png"),
	1: preload("res://sprite/Player/proppick/IACOBISIO_bigprop.png"),
	2: preload("res://sprite/Player/proppick/NAKAKATA_BIG_PRPO.png"),
	3: preload("res://sprite/Player/proppick/andrix_bigprop.png"),
	4: preload("res://sprite/Player/proppick/mencu_proppic.png"),
	5: preload("res://sprite/Player/proppick/perucx_preview.png"),
}
# scala per uniformare l'altezza delle 3 immagini (le sorgenti hanno dimensioni diverse)
const PREVIEW_SCALE := {
	0: 1.0,
	1: 1.2528716,
	2: 0.45,
	3: 0.4,
	4: 0.4,
	5: 0.4,
}

# ordine visivo sinistra -> destra dei personaggi selezionabili
var slots: Array = []
var cursor_index: int = 0

# tempo minimo (in secondi) tra un movimento del cursore e il successivo:
# senza questo, tenendo la levetta/D-pad il cursore scatta a ripetizione
# molto più velocemente di quanto succeda con una singola pressione tastiera.
const TEMPO_TRA_MOVIMENTI := 0.18
var _tempo_ultimo_movimento: float = -999.0


func _ready() -> void:
	slots = [
		{"skin": 1, "btn": bisio_btn},
		{"skin": 0, "btn": tommaso_btn},
		{"skin": 2, "btn": nakakata_btn},
		{"skin": 3, "btn": andrix_btn},
		{"skin": 4, "btn": mencu_btn},
		{"skin": 5, "btn": perucx_btn},
	]

	# il mouse funziona SOLO quando è il turno del giocatore assegnato a tastiera
	# (vedi _mouse_abilitato): se tocca al giocatore col controller, hover e click
	# sono completamente ignorati.
	bisio_btn.mouse_entered.connect(_hover_to.bind(0))
	tommaso_btn.mouse_entered.connect(_hover_to.bind(1))
	nakakata_btn.mouse_entered.connect(_hover_to.bind(2))
	andrix_btn.mouse_entered.connect(_hover_to.bind(3))
	mencu_btn.mouse_entered.connect(_hover_to.bind(4))
	perucx_btn.mouse_entered.connect(_hover_to.bind(5))

	bisio_btn.pressed.connect(_click_to.bind(0))
	tommaso_btn.pressed.connect(_click_to.bind(1))
	nakakata_btn.pressed.connect(_click_to.bind(2))
	andrix_btn.pressed.connect(_click_to.bind(3))
	mencu_btn.pressed.connect(_click_to.bind(4))
	perucx_btn.pressed.connect(_click_to.bind(5))

	GameState.selection_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Solo il dispositivo assegnato al giocatore di turno può muovere il
	# cursore o confermare: l'altro dispositivo viene ignorato del tutto,
	# anche se preme gli stessi tasti/pulsanti di default di Godot.
	var assegnazione: Dictionary = Controlli.i().assegnazioni.get(GameState.selecting_player, {})
	if assegnazione.is_empty():
		return

	if assegnazione.tipo == "controller":
		_gestisci_controller(event, assegnazione)
	else:
		_gestisci_tastiera(event, assegnazione)


func _gestisci_tastiera(event: InputEvent, _assegnazione: Dictionary) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var prefisso: String = "p1_" if GameState.selecting_player == 0 else "p2_"
	if event.is_action_pressed(prefisso + "left"):
		_muovi(-1)
	elif event.is_action_pressed(prefisso + "right"):
		_muovi(1)
	elif event.is_action_pressed(prefisso + "attack"):
		_conferma()


func _gestisci_controller(event: InputEvent, assegnazione: Dictionary) -> void:
	var device: int = assegnazione.device

	if event is InputEventJoypadButton and event.device == device and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			_muovi(-1)
		elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_muovi(1)
		elif event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X:
			_conferma()
	elif event is InputEventJoypadMotion and event.device == device and event.axis == JOY_AXIS_LEFT_X:
		if event.axis_value < -0.5:
			_muovi(-1)
		elif event.axis_value > 0.5:
			_muovi(1)


func _muovi(direzione: int) -> void:
	var adesso := Time.get_ticks_msec() / 1000.0
	if adesso - _tempo_ultimo_movimento < TEMPO_TRA_MOVIMENTI:
		return
	_tempo_ultimo_movimento = adesso
	cursor_index = (cursor_index + direzione + slots.size()) % slots.size()
	_update_cursor()


func _conferma() -> void:
	GameState.choose_skin(slots[cursor_index].skin)


func _mouse_abilitato() -> bool:
	var assegnazione: Dictionary = Controlli.i().assegnazioni.get(GameState.selecting_player, {})
	return assegnazione.get("tipo", "") == "tastiera"


func _hover_to(index: int) -> void:
	if not _mouse_abilitato():
		return
	cursor_index = index
	_update_cursor()


func _click_to(index: int) -> void:
	if not _mouse_abilitato():
		return
	cursor_index = index
	_update_cursor()
	_conferma()


func _refresh() -> void:
	# se il player 1 ha già scelto, "congela" la sua anteprima sul personaggio scelto
	# (indipendentemente dal fatto che abbia confermato con mouse o tastiera)
	if GameState.selecting_player >= 1:
		_freeze_preview(anteprima_p1, GameState.get_skin_for(0), false)

	# l'anteprima del player 2 resta vuota finché non è davvero il suo turno,
	# così non si vede nessun personaggio prima che inizi a scegliere
	anteprima_p2.visible = GameState.selecting_player >= 1

	label.text = "Player %d: scegli il personaggio" % (GameState.selecting_player + 1)
	cursor_index = 0
	_update_cursor()


func _update_cursor() -> void:
	var pulsante: Button = slots[cursor_index].btn
	cursore.position = pulsante.position - Vector2(6, 6)
	cursore.size = pulsante.size + Vector2(12, 12)
	_aggiorna_anteprima_live(slots[cursor_index].skin)


func _aggiorna_anteprima_live(skin: int) -> void:
	# anteprima a sinistra per il player 1, a destra (specchiata) per il player 2
	var e_player_2: bool = GameState.selecting_player == 1
	var anteprima: Sprite2D = anteprima_p2 if e_player_2 else anteprima_p1
	_freeze_preview(anteprima, skin, e_player_2)


func _freeze_preview(anteprima: Sprite2D, skin: int, specchiata: bool) -> void:
	anteprima.texture = PREVIEW_TEXTURES[skin]
	var s: float = PREVIEW_SCALE[skin]
	anteprima.scale = Vector2(-s, s) if specchiata else Vector2(s, s)
