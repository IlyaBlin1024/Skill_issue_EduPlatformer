extends SceneTree

const MODEL_ROOT := "res://assets/production_art/models"
const LEVEL_ROOT := "res://assets/production_art/levels"

const LEVEL_FOLDERS := [
	"tutorial",
	"level_01_variables",
	"level_02_if_else",
	"level_03_loops",
	"level_04_functions",
	"level_05_integration",
]

const BOSS_FOLDERS := [
	"01_threshold_warden",
	"02_logic_spider",
	"03_assembly_golem",
	"04_archivist",
	"05_system_admin",
]

func _initialize() -> void:
	_generate_all_assets()
	print("Production sprites and aligned level tiles generated.")
	quit()


func _generate_all_assets() -> void:
	_generate_enemy_set("%s/characters/enemies/melee_sentinel" % MODEL_ROOT, "melee")
	_generate_enemy_set("%s/characters/enemies/ranged_sentinel" % MODEL_ROOT, "ranged")
	_generate_boss_sets()
	_generate_chests("%s/interactables/chests" % MODEL_ROOT)
	_generate_altars("%s/interactables/altars" % MODEL_ROOT)
	_generate_level_tiles()
	_clean_legacy_sprite_dirs()


func _generate_enemy_set(folder: String, kind: String) -> void:
	_prepare_clean_dir(folder)
	var animations := {
		"%s_idle" % kind: 4,
		"%s_patrol" % kind: 6,
		"%s_telegraph" % kind: 4,
		"%s_hurt" % kind: 3,
		"%s_death" % kind: 5,
		"%s_parried" % kind: 4,
	}
	if kind == "melee":
		animations["melee_attack"] = 6
	else:
		animations["ranged_shoot"] = 6
		animations["ranged_jump_back"] = 6
	for prefix in animations.keys():
		var frame_count := int(animations[prefix])
		for frame_index in range(frame_count):
			var image := _new_image(96, 96)
			_draw_enemy(image, kind, String(prefix), frame_index, frame_count)
			_save_frame(image, folder, String(prefix), frame_index)


func _generate_boss_sets() -> void:
	for folder in BOSS_FOLDERS:
		var target_folder := "%s/bosses/%s" % [MODEL_ROOT, folder]
		_prepare_clean_dir(target_folder)
		var animations: Dictionary = _boss_animation_counts(folder)
		for prefix in animations.keys():
			var frame_count := int(animations[prefix])
			for frame_index in range(frame_count):
				var image := _new_image(256, 256)
				_draw_boss(image, folder, String(prefix), frame_index, frame_count)
				_save_frame(image, target_folder, String(prefix), frame_index)


func _boss_animation_counts(folder: String) -> Dictionary:
	if folder == "02_logic_spider":
		return {
			"idle": 4,
			"crawl": 6,
			"telegraph_branch": 4,
			"attack_branch": 6,
			"hurt": 3,
			"death": 6,
		}
	if folder == "03_assembly_golem":
		return {
			"idle": 4,
			"walk": 6,
			"telegraph_loop": 4,
			"attack_loop": 6,
			"hurt": 3,
			"death": 6,
		}
	if folder == "04_archivist":
		return {
			"idle": 4,
			"float": 6,
			"telegraph_function": 4,
			"attack_function": 6,
			"hurt": 3,
			"death": 6,
		}
	if folder == "05_system_admin":
		return {
			"idle": 4,
			"move": 6,
			"telegraph_system": 4,
			"attack_system": 6,
			"teleport_dissolve": 5,
			"teleport_materialize": 5,
			"hurt": 3,
			"death": 6,
		}
	return {
		"idle": 4,
		"move": 6,
		"telegraph": 4,
		"attack_threshold": 6,
		"hurt": 3,
		"death": 6,
	}


func _generate_chests(folder: String) -> void:
	_prepare_clean_dir(folder)
	var animations := {
		"chest_idle": 4,
		"chest_open": 6,
		"chest_locked": 4,
	}
	for prefix in animations.keys():
		var frame_count := int(animations[prefix])
		for frame_index in range(frame_count):
			var image := _new_image(128, 128)
			_draw_chest(image, String(prefix), frame_index, frame_count)
			_save_frame(image, folder, String(prefix), frame_index)


func _generate_altars(folder: String) -> void:
	_prepare_clean_dir(folder)
	var animations := {
		"altar_idle": 4,
		"altar_activate": 6,
		"altar_complete": 6,
	}
	for prefix in animations.keys():
		var frame_count := int(animations[prefix])
		for frame_index in range(frame_count):
			var image := _new_image(128, 128)
			_draw_altar(image, String(prefix), frame_index, frame_count)
			_save_frame(image, folder, String(prefix), frame_index)


func _generate_level_tiles() -> void:
	for folder in LEVEL_FOLDERS:
		var root := "%s/%s" % [LEVEL_ROOT, folder]
		_save_image(_build_ground_tile(), "%s/tilesets/tileset_ground.png" % root)
		_save_image(_build_wall_tile(), "%s/tilesets/tileset_walls.png" % root)
		_save_image(_build_platform_tile(), "%s/platforms/platform_one_way.png" % root)


func _draw_enemy(image: Image, kind: String, prefix: String, frame_index: int, frame_count: int) -> void:
	var t := float(frame_index) / maxf(float(frame_count - 1), 1.0)
	var bob := int(round(sin(t * TAU) * 2.0))
	var step := int(round(sin(t * TAU) * 3.0))
	var cloak := _color("#10131d")
	var cloak_shadow := _color("#05060b")
	var leather := _color("#151925")
	var accent := _color("#ff4b64") if kind == "melee" else _color("#38d7ff")
	var metal := _color("#cbd8ef")
	var shadow := _color("#090a12", 0.52)
	var x := 48
	var foot_y := 86
	if prefix.ends_with("patrol") or prefix.ends_with("jump_back"):
		x += step
	if prefix.ends_with("hurt") or prefix.ends_with("parried"):
		x -= 4 - frame_index * 2
	if prefix.ends_with("death"):
		bob += frame_index * 3

	_ellipse(image, x, foot_y - 2, 22, 5, shadow)

	var robe_top := foot_y - 44 + bob
	_tapered_rect(image, x, robe_top, 12, 22, 38, cloak)
	_tapered_rect(image, x, robe_top + 7, 7, 13, 27, cloak_shadow)
	_rect(image, x - 1, robe_top + 11, 2, 23, _color("#283042"))
	_rect(image, x - 10, robe_top + 23, 4, 17, leather)
	_rect(image, x + 6, robe_top + 23, 4, 17, leather)
	_rect(image, x - 13 + step, foot_y - 7 + bob, 9, 4, metal)
	_rect(image, x + 4 - step, foot_y - 7 + bob, 9, 4, metal)

	_ellipse(image, x, foot_y - 55 + bob, 13, 12, cloak)
	_ellipse(image, x, foot_y - 52 + bob, 9, 8, _color("#070911"))
	_rect(image, x + 2, foot_y - 52 + bob, 4, 3, accent)
	_rect(image, x - 9, foot_y - 44 + bob, 18, 2, _color("#05050a", 0.5))

	_line(image, x - 9, robe_top + 10, x - 14, robe_top + 25, leather)
	_line(image, x - 8, robe_top + 10, x - 13, robe_top + 25, leather)
	_line(image, x + 9, robe_top + 10, x + 14, robe_top + 25, leather)
	_line(image, x + 8, robe_top + 10, x + 13, robe_top + 25, leather)

	if kind == "melee":
		var blade_raise := 0
		if prefix.ends_with("telegraph"):
			blade_raise = -8 - frame_index * 2
		elif prefix.ends_with("attack"):
			blade_raise = int(lerpf(-18.0, 12.0, t))
			x += int(lerpf(-3.0, 8.0, t))
		_line(image, x + 17, foot_y - 40 + bob, x + 34, foot_y - 67 + bob + blade_raise, metal)
		_line(image, x + 18, foot_y - 39 + bob, x + 35, foot_y - 66 + bob + blade_raise, _color("#f6f2ba"))
		_rect(image, x + 13, foot_y - 42 + bob, 9, 4, _color("#6c4422"))
	else:
		var recoil := 0
		if prefix.ends_with("shoot"):
			recoil = int(lerpf(4.0, -6.0, t))
		elif prefix.ends_with("telegraph"):
			recoil = -frame_index
		_line(image, x + 15 + recoil, foot_y - 39 + bob, x + 34 + recoil, foot_y - 43 + bob, _color("#203a63"))
		_line(image, x + 15 + recoil, foot_y - 38 + bob, x + 34 + recoil, foot_y - 42 + bob, accent)
		_diamond(image, x + 36 + recoil, foot_y - 43 + bob, 5, accent)
		if prefix.ends_with("shoot") and frame_index >= 2:
			_diamond(image, x + 43 + frame_index * 2, foot_y - 43 + bob, 3, _color("#ffd56a", 0.82))
		if prefix.ends_with("jump_back"):
			_line(image, x - 14, foot_y - 18 + bob, x - 30, foot_y - 8 + bob, _color("#8be9ff", 0.7))

	if prefix.ends_with("hurt"):
		_rect(image, x - 19, foot_y - 56 + bob, 38, 8, _color("#ffffff", 0.35))
	if prefix.ends_with("parried"):
		_diamond(image, x - 26, foot_y - 39 + bob, 9 + frame_index, _color("#81f7ff", 0.85))
	if prefix.ends_with("death"):
		_rect(image, x - 19, foot_y - 22 + bob, 38, 10, _color("#11121c", 0.75))


func _draw_boss(image: Image, folder: String, prefix: String, frame_index: int, frame_count: int) -> void:
	var t := float(frame_index) / maxf(float(frame_count - 1), 1.0)
	var bob := int(round(sin(t * TAU) * 4.0))
	var foot_y := 238
	var x := 128
	if prefix.contains("hurt"):
		x += frame_index * 4 - 4
	if prefix.contains("death"):
		bob += frame_index * 6
	if folder == "02_logic_spider":
		_draw_spider_boss(image, x, foot_y, bob, prefix, frame_index, t)
	elif folder == "03_assembly_golem":
		_draw_golem_boss(image, x, foot_y, bob, prefix, frame_index, t)
	elif folder == "04_archivist":
		_draw_archivist_boss(image, x, foot_y, bob, prefix, frame_index, t)
	elif folder == "05_system_admin":
		_draw_admin_boss(image, x, foot_y, bob, prefix, frame_index, t)
	else:
		_draw_warden_boss(image, x, foot_y, bob, prefix, frame_index, t)


func _draw_warden_boss(image: Image, x: int, foot_y: int, bob: int, prefix: String, frame_index: int, t: float) -> void:
	_ellipse(image, x, foot_y - 3, 54, 9, _color("#080910", 0.5))
	_rect(image, x - 34, foot_y - 110 + bob, 68, 92, _color("#523c82"))
	_rect(image, x - 25, foot_y - 100 + bob, 50, 74, _color("#a74cc8"))
	_rect(image, x - 30, foot_y - 132 + bob, 60, 30, _color("#291d45"))
	_rect(image, x - 18, foot_y - 125 + bob, 36, 12, _color("#f0db8a"))
	_diamond(image, x, foot_y - 71 + bob, 24, _color("#ffdb60"))
	_rect(image, x - 42, foot_y - 88 + bob, 15, 54, _color("#ead07c"))
	_rect(image, x + 27, foot_y - 88 + bob, 15, 54, _color("#ead07c"))
	var blade_y := int(lerpf(-22.0, 18.0, t)) if prefix.contains("attack") else 0
	_line(image, x + 45, foot_y - 121 + bob + blade_y, x + 78, foot_y - 36 + bob - blade_y, _color("#eaf5ff"))
	_line(image, x + 49, foot_y - 121 + bob + blade_y, x + 82, foot_y - 36 + bob - blade_y, _color("#60d8ff"))
	_draw_boss_state_fx(image, x, foot_y, bob, prefix, frame_index, _color("#f5c7ff"))


func _draw_spider_boss(image: Image, x: int, foot_y: int, bob: int, prefix: String, frame_index: int, t: float) -> void:
	_ellipse(image, x, foot_y - 4, 70, 10, _color("#09060d", 0.55))
	for index in range(4):
		var y := foot_y - 44 + index * 9 + bob
		var swing := int(sin(t * TAU + float(index)) * 8.0)
		_line(image, x - 22, y, x - 82 + swing, y + 28, _color("#642a82"))
		_line(image, x + 22, y, x + 82 - swing, y + 28, _color("#642a82"))
		_line(image, x - 82 + swing, y + 28, x - 98 + swing, y + 46, _color("#2a1239"))
		_line(image, x + 82 - swing, y + 28, x + 98 - swing, y + 46, _color("#2a1239"))
	_ellipse(image, x, foot_y - 76 + bob, 44, 35, _color("#5b226f"))
	_ellipse(image, x, foot_y - 116 + bob, 32, 28, _color("#8d3fc8"))
	_rect(image, x - 18, foot_y - 124 + bob, 8, 6, _color("#ff6aff"))
	_rect(image, x + 10, foot_y - 124 + bob, 8, 6, _color("#ff6aff"))
	if prefix.contains("attack") or prefix.contains("telegraph"):
		_line(image, x, foot_y - 111 + bob, x + 52, foot_y - 146 + bob - frame_index * 4, _color("#b96cff"))
		_line(image, x, foot_y - 111 + bob, x - 52, foot_y - 146 + bob - frame_index * 4, _color("#b96cff"))
	_draw_boss_state_fx(image, x, foot_y, bob, prefix, frame_index, _color("#ff8cff"))


func _draw_golem_boss(image: Image, x: int, foot_y: int, bob: int, prefix: String, frame_index: int, t: float) -> void:
	_ellipse(image, x, foot_y - 3, 64, 10, _color("#090b10", 0.5))
	var step := int(sin(t * TAU) * 6.0)
	_rect(image, x - 52, foot_y - 106 + bob, 104, 76, _color("#39445b"))
	_rect(image, x - 40, foot_y - 96 + bob, 80, 54, _color("#65708b"))
	_rect(image, x - 32, foot_y - 142 + bob, 64, 38, _color("#2b3349"))
	_rect(image, x - 18, foot_y - 131 + bob, 36, 9, _color("#75e4ff"))
	_rect(image, x - 70, foot_y - 96 + bob - step, 22, 66, _color("#475574"))
	_rect(image, x + 48, foot_y - 96 + bob + step, 22, 66, _color("#475574"))
	_rect(image, x - 42 + step, foot_y - 32 + bob, 26, 25, _color("#2d364e"))
	_rect(image, x + 16 - step, foot_y - 32 + bob, 26, 25, _color("#2d364e"))
	if prefix.contains("attack") or prefix.contains("telegraph"):
		_rect(image, x - 88, foot_y - 89 + bob, 28 + frame_index * 8, 22, _color("#f9a646"))
		_rect(image, x + 60 - frame_index * 2, foot_y - 89 + bob, 28 + frame_index * 8, 22, _color("#f9a646"))
	_draw_boss_state_fx(image, x, foot_y, bob, prefix, frame_index, _color("#7be5ff"))


func _draw_archivist_boss(image: Image, x: int, foot_y: int, bob: int, prefix: String, frame_index: int, t: float) -> void:
	_ellipse(image, x, foot_y - 12, 55, 8, _color("#080a12", 0.45))
	_rect(image, x - 30, foot_y - 122 + bob, 60, 90, _color("#23306c"))
	_rect(image, x - 21, foot_y - 113 + bob, 42, 66, _color("#4363c9"))
	_ellipse(image, x, foot_y - 145 + bob, 24, 24, _color("#d9d7ff"))
	_rect(image, x - 45, foot_y - 92 + bob, 26, 34, _color("#f0d989"))
	_rect(image, x + 19, foot_y - 92 + bob, 26, 34, _color("#f0d989"))
	_line(image, x - 42, foot_y - 80 + bob, x + 42, foot_y - 80 + bob, _color("#5df1ff"))
	if prefix.contains("attack") or prefix.contains("telegraph"):
		for index in range(5):
			_diamond(image, x - 56 + index * 28, foot_y - 162 + bob - frame_index * 3, 8, _color("#95ffdf", 0.9))
	_draw_boss_state_fx(image, x, foot_y, bob, prefix, frame_index, _color("#e9dcff"))


func _draw_admin_boss(image: Image, x: int, foot_y: int, bob: int, prefix: String, frame_index: int, t: float) -> void:
	var alpha := 1.0
	if prefix.contains("dissolve"):
		alpha = maxf(0.15, 1.0 - t)
	elif prefix.contains("materialize"):
		alpha = maxf(0.15, t)
	_ellipse(image, x, foot_y - 3, 62, 9, _color("#080b14", 0.4 * alpha))
	_rect(image, x - 42, foot_y - 119 + bob, 84, 82, _color("#1f254d", alpha))
	_rect(image, x - 28, foot_y - 105 + bob, 56, 48, _color("#2f6bff", alpha))
	_rect(image, x - 25, foot_y - 102 + bob, 50, 11, _color("#ff4bd8", alpha))
	_rect(image, x - 20, foot_y - 151 + bob, 40, 34, _color("#151a36", alpha))
	_rect(image, x - 13, foot_y - 140 + bob, 26, 8, _color("#7cf9ff", alpha))
	for index in range(3):
		var side := -1 if index % 2 == 0 else 1
		_line(image, x + side * 40, foot_y - 94 + bob + index * 12, x + side * 78, foot_y - 116 + bob + index * 10, _color("#ff4bd8", alpha))
		_diamond(image, x + side * 84, foot_y - 119 + bob + index * 10, 8, _color("#7cf9ff", alpha))
	if prefix.contains("attack") or prefix.contains("telegraph"):
		for index in range(4):
			_rect(image, x - 82 + index * 44, foot_y - 171 + bob - frame_index * 2, 18, 18, _color("#ff4bd8", 0.7 * alpha))
	_draw_boss_state_fx(image, x, foot_y, bob, prefix, frame_index, _color("#7cf9ff", alpha))


func _draw_boss_state_fx(image: Image, x: int, foot_y: int, bob: int, prefix: String, frame_index: int, fx_color: Color) -> void:
	if prefix.contains("telegraph"):
		_diamond(image, x, foot_y - 170 + bob, 22 + frame_index * 3, fx_color)
	if prefix.contains("hurt"):
		_rect(image, x - 54, foot_y - 132 + bob, 108, 16, _color("#ffffff", 0.34))
	if prefix.contains("death"):
		_rect(image, x - 72, foot_y - 78 + bob, 144, 26, _color("#11121a", 0.68))


func _draw_chest(image: Image, prefix: String, frame_index: int, frame_count: int) -> void:
	var t := float(frame_index) / maxf(float(frame_count - 1), 1.0)
	var lid_offset := 0
	if prefix == "chest_open":
		lid_offset = -int(round(t * 28.0))
	var glow := _color("#5cf6ff", 0.5 + t * 0.35) if prefix == "chest_open" else _color("#ffd06a", 0.35)
	_ellipse(image, 64, 116, 40, 7, _color("#080810", 0.45))
	_rect(image, 22, 62, 84, 46, _color("#7a461d"))
	_rect(image, 29, 69, 70, 31, _color("#b56a28"))
	_rect(image, 18, 45 + lid_offset, 92, 28, _color("#5f3717"))
	_rect(image, 25, 51 + lid_offset, 78, 14, _color("#d18a36"))
	_rect(image, 58, 70, 12, 18, _color("#f6d46f"))
	_rect(image, 14, 72, 14, 32, _color("#322011"))
	_rect(image, 100, 72, 14, 32, _color("#322011"))
	_rect(image, 30, 82, 68, 5, glow)
	if prefix == "chest_locked":
		_rect(image, 52, 45, 24, 30, _color("#1d1d25", 0.75))
		_rect(image, 57, 37, 14, 15, _color("#a78342"))
	if prefix == "chest_open":
		for index in range(5):
			_diamond(image, 36 + index * 14, 56 + lid_offset - index % 2 * 6, 4 + frame_index, _color("#7dfff6", 0.75))


func _draw_altar(image: Image, prefix: String, frame_index: int, frame_count: int) -> void:
	var t := float(frame_index) / maxf(float(frame_count - 1), 1.0)
	var flame := int(round(sin(t * TAU) * 5.0))
	var active := prefix != "altar_idle"
	_ellipse(image, 64, 118, 42, 6, _color("#080810", 0.42))
	_rect(image, 30, 82, 68, 28, _color("#4a3658"))
	_rect(image, 36, 72, 56, 14, _color("#765f92"))
	_rect(image, 42, 56, 44, 20, _color("#2a263f"))
	_rect(image, 50, 40, 28, 20, _color("#151827"))
	_diamond(image, 64, 51 + flame, 14 + (frame_index if active else 0), _color("#53f5ff", 0.85))
	if active:
		_diamond(image, 64, 48 + flame, 28 + frame_index * 2, _color("#ff51df", 0.28))
		_line(image, 24, 72, 104, 72, _color("#ffd568", 0.8))
	if prefix == "altar_complete":
		for index in range(6):
			_diamond(image, 29 + index * 14, 37 + (index % 2) * 8, 5, _color("#d9ff75", 0.85))


func _build_ground_tile() -> Image:
	var image := _new_image(64, 32)
	_rect(image, 0, 0, 64, 4, _color("#d8bb61"))
	_rect(image, 0, 4, 64, 7, _color("#8066c6"))
	_rect(image, 0, 11, 64, 21, _color("#4c366f"))
	for x in range(0, 64, 8):
		_line(image, x, 11, x, 31, _color("#24182f", 0.85))
	for y in range(14, 32, 8):
		_line(image, 0, y, 63, y, _color("#8b6d4b", 0.65))
	for x in range(6, 64, 16):
		_diamond(image, x, 8, 4, _color("#a850d7"))
	return image


func _build_wall_tile() -> Image:
	var image := _new_image(64, 64)
	_rect(image, 0, 0, 64, 64, _color("#100b1f"))
	for y in range(0, 64, 16):
		for x in range(0, 64, 16):
			var brick_color := _color("#25183d") if int((x + y) / 16) % 2 == 0 else _color("#1c142f")
			_rect(image, x + 2, y + 2, 13, 13, brick_color)
			_rect(image, x + 2, y + 2, 13, 2, _color("#6f55ad", 0.88))
			_rect(image, x + 2, y + 2, 2, 13, _color("#5b448e", 0.72))
			_rect(image, x + 14, y + 3, 1, 12, _color("#070512", 0.75))
			_rect(image, x + 3, y + 14, 12, 1, _color("#070512", 0.72))
	for x in range(0, 64, 16):
		_rect(image, x, 0, 2, 64, _color("#8c6be2", 0.74))
	for y in range(0, 64, 16):
		_rect(image, 0, y, 64, 2, _color("#8c6be2", 0.74))
	_rect(image, 0, 0, 64, 4, _color("#b28cff", 0.95))
	_rect(image, 0, 0, 4, 64, _color("#8061c8", 0.9))
	_rect(image, 60, 0, 4, 64, _color("#06040f", 0.75))
	_rect(image, 0, 60, 64, 4, _color("#06040f", 0.75))
	for x in range(8, 64, 16):
		for y in range(8, 64, 16):
			_diamond(image, x, y, 3, _color("#9b4fe8", 0.8))
	return image


func _build_platform_tile() -> Image:
	var image := _new_image(128, 18)
	_rect(image, 0, 0, 128, 4, _color("#ead16a"))
	_rect(image, 0, 4, 128, 10, _color("#7b48d9"))
	_rect(image, 0, 14, 128, 4, _color("#171226"))
	for x in range(10, 128, 18):
		_diamond(image, x, 9, 5, _color("#82efff"))
	return image


func _new_image(width: int, height: int) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	return image


func _save_frame(image: Image, folder: String, prefix: String, frame_index: int) -> void:
	_save_image(image, "%s/%s_%02d.png" % [folder, prefix, frame_index + 1])


func _save_image(image: Image, res_path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("Could not save %s, error %s" % [res_path, error])


func _prepare_clean_dir(res_path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(absolute_path)
	var dir := DirAccess.open(res_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and _is_generated_artifact(file_name):
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _clean_legacy_sprite_dirs() -> void:
	var legacy_dirs := [
		"res://assets/production_art/characters/enemies/melee_sentinel/spritesheets",
		"res://assets/production_art/characters/enemies/ranged_sentinel/spritesheets",
		"res://assets/production_art/interactables/chests/spritesheets",
		"res://assets/production_art/interactables/altars/spritesheets",
	]
	for boss_folder in BOSS_FOLDERS:
		legacy_dirs.append("res://assets/production_art/bosses/%s/spritesheets" % boss_folder)
	for legacy_dir in legacy_dirs:
		_prepare_clean_dir(String(legacy_dir))


func _is_generated_artifact(file_name: String) -> bool:
	return file_name.ends_with(".png") or file_name.ends_with(".png.import") or file_name.ends_with(".json")


func _color(hex_value: String, alpha: float = 1.0) -> Color:
	var color := Color.from_string(hex_value, Color.WHITE)
	color.a = alpha
	return color


func _put(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height() or color.a <= 0.0:
		return
	var dst := image.get_pixel(x, y)
	var out_alpha := color.a + dst.a * (1.0 - color.a)
	if out_alpha <= 0.0:
		return
	var out := Color(
		(color.r * color.a + dst.r * dst.a * (1.0 - color.a)) / out_alpha,
		(color.g * color.a + dst.g * dst.a * (1.0 - color.a)) / out_alpha,
		(color.b * color.a + dst.b * dst.a * (1.0 - color.a)) / out_alpha,
		out_alpha
	)
	image.set_pixel(x, y, out)


func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for yy in range(y, y + height):
		for xx in range(x, x + width):
			_put(image, xx, yy, color)


func _tapered_rect(image: Image, cx: int, y: int, top_width: int, bottom_width: int, height: int, color: Color) -> void:
	for row in range(height):
		var ratio := float(row) / maxf(float(height - 1), 1.0)
		var width := int(round(lerpf(float(top_width), float(bottom_width), ratio)))
		_rect(image, cx - int(width * 0.5), y + row, width, 1, color)


func _ellipse(image: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	if rx <= 0 or ry <= 0:
		return
	for yy in range(cy - ry, cy + ry + 1):
		for xx in range(cx - rx, cx + rx + 1):
			var dx := float(xx - cx) / float(rx)
			var dy := float(yy - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				_put(image, xx, yy, color)


func _diamond(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for yy in range(cy - radius, cy + radius + 1):
		for xx in range(cx - radius, cx + radius + 1):
			if abs(xx - cx) + abs(yy - cy) <= radius:
				_put(image, xx, yy, color)


func _line(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var steps := maxi(abs(x1 - x0), abs(y1 - y0))
	if steps <= 0:
		_put(image, x0, y0, color)
		return
	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var xx := int(round(float(x0) + (float(x1 - x0) * t)))
		var yy := int(round(float(y0) + (float(y1 - y0) * t)))
		_put(image, xx, yy, color)
