extends Control

# Script "regista" della UI unificata.
# Sostituisce toselect.gd / quit.gd / apri_impostazioni.gd / toonline.gd:
# invece di cambiare scena, mostra/nasconde i pannelli figli di questo nodo.

@onready var menu_principale: Node2D = $MenuPrincipale
@onready var impostazioni: Control = $Impostazioni
@onready var selezione_personaggio: Node2D = $SelezionePersonaggio
@onready var network_menu: Control = $NetworkMenu
@onready var selezione_controlli: Control = $SelezioneControlli
@onready var selezione_mappa: Control = $SelezioneMappa
@onready var bot_toggle: CheckButton = $SelezionePersonaggio/OpzioniBotLayer/OpzioniBot/Contenuto/BotToggle
@onready var bot_input_mode: OptionButton = $SelezionePersonaggio/OpzioniBotLayer/OpzioniBot/Contenuto/BotInputMode
@onready var bot_options: Control = $SelezionePersonaggio/OpzioniBotLayer/OpzioniBot

func _ready() -> void:
	GameState.selection_finished.connect(mostra_selezione_mappa)
	selezione_mappa.mappa_scelta.connect(_on_mappa_scelta)
	bot_toggle.button_pressed = GameState.bot_enabled
	bot_toggle.toggled.connect(_on_bot_toggled)
	bot_input_mode.add_item("Tastiera / mouse", 0)
	bot_input_mode.add_item("Controller", 1)
	bot_input_mode.selected = 1 if GameState.bot_player_uses_pad else 0
	bot_input_mode.item_selected.connect(_on_bot_input_mode_selected)
	bot_input_mode.disabled = Input.get_connected_joypads().is_empty()
	bot_input_mode.visible = GameState.bot_enabled
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_mostra_solo(menu_principale)


func _on_bot_toggled(enabled: bool) -> void:
	GameState.bot_enabled = enabled
	bot_input_mode.visible = enabled
	_applica_dispositivo_contro_bot(GameState.bot_player_uses_pad)


func _on_bot_input_mode_selected(index: int) -> void:
	GameState.bot_player_uses_pad = index == 1
	_applica_dispositivo_contro_bot(GameState.bot_player_uses_pad)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	bot_input_mode.disabled = Input.get_connected_joypads().is_empty()
	if bot_input_mode.disabled and GameState.bot_player_uses_pad:
		GameState.bot_player_uses_pad = false
		bot_input_mode.select(0)
		_applica_dispositivo_contro_bot(false)


func _applica_dispositivo_contro_bot(usa_pad: bool) -> void:
	if not GameState.bot_enabled:
		return
	var controlli := Controlli.i()
	if usa_pad and not Input.get_connected_joypads().is_empty():
		controlli.imposta_giocatore_contro_bot(true)
	else:
		GameState.bot_player_uses_pad = false
		bot_input_mode.select(0)
		controlli.imposta_giocatore_contro_bot(false)


func start_local_game() -> void:
	mostra_selezione_controlli()

func mostra_menu_principale() -> void:
	_mostra_solo(menu_principale)

func mostra_selezione_controlli() -> void:
	_mostra_solo(selezione_controlli)

func mostra_selezione_personaggio() -> void:
	# toselect.gd inizializzava lo stato tramite l'autoload GameState
	# prima di mostrare la schermata: manteniamo lo stesso comportamento.
	GameState.start_selection()
	_mostra_solo(selezione_personaggio)

func mostra_selezione_mappa() -> void:
	_mostra_solo(selezione_mappa)

func _on_mappa_scelta(_mappa: Dictionary) -> void:
	# la mappa resta in SelettoreMappa.corrente, da leggere nel livello
	get_tree().change_scene_to_file("res://level.tscn")

func mostra_network_menu() -> void:
	GameState.bot_enabled = false
	GameState.set_player_config(1, GameState.get_skin_for(1), GameState.get_device_for(1), false)
	bot_toggle.button_pressed = false
	bot_input_mode.visible = false
	_mostra_solo(network_menu)

func mostra_impostazioni() -> void:
	_mostra_solo(impostazioni)

func torna_al_menu() -> void:
	# Se si torna al menu dalla schermata di rete con una connessione avviata
	# (host o client), la chiudiamo: Network.stop() non fa nulla se
	# non c'era nessuna connessione attiva.
	Network.stop()
	_mostra_solo(menu_principale)

func esci_gioco() -> void:
	get_tree().quit()

func _mostra_solo(pannello_da_mostrare: Node) -> void:
	for pannello in [menu_principale, impostazioni, selezione_personaggio, network_menu, selezione_controlli, selezione_mappa]:
		pannello.visible = (pannello == pannello_da_mostrare)
	# CanvasLayer non eredita la visibilità del Node2D genitore.
	bot_options.visible = pannello_da_mostrare == selezione_personaggio
