# sound_bank.gd
#
# PURPOSE
#   Every sound file the app uses, in one place, so the credits (CREDITS.md,
#   ui/credits.gd) are easy to check against what is actually loaded.
#   Downloaded sounds are CC0; see CREDITS.md for sources.
#
# HOW IT FITS
#   UI sounds are played by ui/sound_fx.gd. Plant loops are chosen by each
#   plant visual (PlantVisual3D.get_sound_loop()) and played by PlantView.
#   Loop points are set in the .import files (loop / edit/loop_mode).
class_name SoundBank
extends RefCounted

# --- interface (Kenney "Interface Sounds") ---
const CLICK: AudioStream = preload("res://assets/audio/ui/click.ogg")
const TOGGLE: AudioStream = preload("res://assets/audio/ui/toggle.ogg")
const SUCCESS: AudioStream = preload("res://assets/audio/ui/success.ogg")
const STEP_DONE: AudioStream = preload("res://assets/audio/ui/step_done.ogg")
const FAIL: AudioStream = preload("res://assets/audio/ui/fail.ogg")

# --- plants ---
const HARD_STOP: AudioStream = preload("res://assets/audio/plant/hard_stop.ogg")
const MOTOR_WHINE: AudioStream = preload("res://assets/audio/plant/motor_whine.wav")  # synthesized
const HEATER_HISS: AudioStream = preload("res://assets/audio/plant/heater_hiss.wav")  # synthesized
const ENGINE_LOOP: AudioStream = preload("res://assets/audio/plant/engine_loop.wav")
const PROPELLER_LOOP: AudioStream = preload("res://assets/audio/plant/propeller_loop.ogg")
const WINCH_LOOP: AudioStream = preload("res://assets/audio/plant/winch_loop.mp3")
