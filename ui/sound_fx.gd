# sound_fx.gd
#
# PURPOSE
#   Interface sounds (A/V patch): a soft click for every button, a tick for
#   every checkbox, and chimes for challenge / lesson results.
#
# HOW IT FITS
#   main_screen.gd adds ONE SoundFx node. It watches the scene tree and hooks
#   every BaseButton (and TabBar) as it appears, so no panel needs sound code.
#   A control can opt out with set_meta("silent", true).
#   Other code plays a chime with SoundFx.play(SoundBank.SUCCESS).
#   Volume and mute come from DisplaySettings.get_gain(false).
#   Clicks only sound right after a real mouse/touch press, so code that sets
#   a checkbox while building a panel stays silent.
class_name SoundFx
extends Node

const INTERFACE_GAIN: float = 0.5  # TUNABLE: clicks are quiet; chimes play at CHIME_GAIN
const CHIME_GAIN: float = 0.8
const VOICES: int = 4
const USER_CLICK_WINDOW_MS: int = 400  # a button signal this soon after a press = the user did it

static var _instance: SoundFx

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_press_ms: int = -100000


func _ready() -> void:
	_instance = self
	for index in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)


func _input(event: InputEvent) -> void:
	# Press OR release: buttons fire on release, which can be long after the press.
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_last_press_ms = Time.get_ticks_msec()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


# Plays an interface sound (no-op without a SoundFx node, e.g. in tests).
static func play(stream: AudioStream, gain: float = CHIME_GAIN) -> void:
	if _instance != null:
		_instance._play(stream, gain)


func _play(stream: AudioStream, gain: float) -> void:
	var volume := gain * DisplaySettings.get_gain(false)
	if volume < 0.002:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = linear_to_db(volume)
	player.play()


func _hook_tree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_tree(child)


func _on_node_added(node: Node) -> void:
	if node.has_meta("silent"):
		return
	if node is BaseButton:
		var button := node as BaseButton
		if button.toggle_mode:
			if not button.toggled.is_connected(_on_toggled):
				button.toggled.connect(_on_toggled)
		elif not button.pressed.is_connected(_on_pressed):
			button.pressed.connect(_on_pressed)
	elif node is TabBar:
		var tabs := node as TabBar
		if not tabs.tab_clicked.is_connected(_on_tab_clicked):
			tabs.tab_clicked.connect(_on_tab_clicked)


func _user_just_clicked() -> bool:
	return Time.get_ticks_msec() - _last_press_ms <= USER_CLICK_WINDOW_MS


func _on_pressed() -> void:
	if _user_just_clicked():
		_play(SoundBank.CLICK, INTERFACE_GAIN)


func _on_toggled(_on: bool) -> void:
	if _user_just_clicked():
		_play(SoundBank.TOGGLE, INTERFACE_GAIN)


func _on_tab_clicked(_tab: int) -> void:
	if _user_just_clicked():
		_play(SoundBank.CLICK, INTERFACE_GAIN)
