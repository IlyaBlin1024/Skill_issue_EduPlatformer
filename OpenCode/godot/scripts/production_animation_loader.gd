extends RefCounted
class_name ProductionAnimationLoader


static func create_sprite(parent: Node, current_sprite: AnimatedSprite2D, fallback_visual: CanvasItem, directories: Array, animations: Dictionary, options: Dictionary = {}) -> AnimatedSprite2D:
	if current_sprite != null and is_instance_valid(current_sprite):
		if current_sprite.get_parent() != null:
			current_sprite.get_parent().remove_child(current_sprite)
		current_sprite.free()

	var frames := build_sprite_frames(directories, animations, options)
	if frames == null:
		if fallback_visual != null and is_instance_valid(fallback_visual):
			if bool(options.get("hide_fallback_on_missing", false)):
				_hide_fallback_visual(fallback_visual)
			else:
				fallback_visual.visible = true
		return null

	var sprite := AnimatedSprite2D.new()
	sprite.name = String(options.get("name", "ProductionSprite"))
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = frames
	sprite.z_index = int(options.get("z_index", 0))
	sprite.position = sprite_position_from_visual(fallback_visual, Vector2i(options.get("canvas_size", Vector2i(96, 96))), int(options.get("foot_margin", 4)))
	parent.add_child(sprite)
	if fallback_visual != null and is_instance_valid(fallback_visual) and fallback_visual.get_parent() == parent:
		parent.move_child(sprite, fallback_visual.get_index() + 1)
	if fallback_visual != null and is_instance_valid(fallback_visual):
		_hide_fallback_visual(fallback_visual)
	sprite.play(String(options.get("initial_animation", "idle")))
	return sprite


static func build_sprite_frames(directories: Array, animations: Dictionary, options: Dictionary = {}) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")

	var loaded_animation_count := 0
	for animation_name in animations.keys():
		var animation_info: Dictionary = animations[animation_name]
		var prefix := String(animation_info.get("prefix", animation_name))
		var frame_files := _find_animation_frame_files(directories, prefix)
		var animation_loaded := false

		if not frame_files.is_empty():
			_add_animation(frames, String(animation_name), animation_info)
			for file_path in frame_files:
				var texture := _load_normalized_texture(file_path, animation_info, options)
				if texture != null:
					frames.add_frame(String(animation_name), texture)
			animation_loaded = frames.get_frame_count(String(animation_name)) > 0
		else:
			var sheet_path := _find_spritesheet_path(directories, prefix)
			if not sheet_path.is_empty():
				_add_animation(frames, String(animation_name), animation_info)
				animation_loaded = _add_spritesheet_frames(frames, String(animation_name), sheet_path, animation_info, options)

		if animation_loaded:
			loaded_animation_count += 1
		elif frames.has_animation(String(animation_name)):
			frames.remove_animation(String(animation_name))

	return frames if loaded_animation_count > 0 else null


static func sprite_position_from_visual(fallback_visual: CanvasItem, canvas_size: Vector2i, foot_margin: int) -> Vector2:
	if fallback_visual is Control:
		var control := fallback_visual as Control
		var bottom := control.position.y + control.size.y
		return Vector2(control.position.x + control.size.x * 0.5, bottom - (float(canvas_size.y) * 0.5 - float(foot_margin)))
	return Vector2(0.0, -(float(canvas_size.y) * 0.5 - float(foot_margin)))


static func _hide_fallback_visual(fallback_visual: CanvasItem) -> void:
	fallback_visual.visible = false
	fallback_visual.modulate = Color(fallback_visual.modulate.r, fallback_visual.modulate.g, fallback_visual.modulate.b, 0.0)
	fallback_visual.self_modulate = Color(fallback_visual.self_modulate.r, fallback_visual.self_modulate.g, fallback_visual.self_modulate.b, 0.0)
	if fallback_visual is ColorRect:
		var color_rect := fallback_visual as ColorRect
		color_rect.color = Color(color_rect.color.r, color_rect.color.g, color_rect.color.b, 0.0)
	if fallback_visual is Control:
		var control := fallback_visual as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in fallback_visual.get_children():
		if child is CanvasItem:
			_hide_fallback_visual(child as CanvasItem)


static func _add_animation(frames: SpriteFrames, animation_name: String, animation_info: Dictionary) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, float(animation_info.get("fps", 8.0)))
	frames.set_animation_loop(animation_name, bool(animation_info.get("loop", true)))


static func _find_animation_frame_files(directories: Array, prefix: String) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for directory_path_variant in directories:
		var directory_path := String(directory_path_variant)
		var dir := DirAccess.open(directory_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and _is_animation_frame(file_name, prefix):
				var resource_path := "%s/%s" % [directory_path, _resource_file_name(file_name)]
				if not seen.has(resource_path):
					seen[resource_path] = true
					result.append(resource_path)
			file_name = dir.get_next()
		dir.list_dir_end()
	result.sort_custom(_sort_frame_paths)
	return result


static func _find_spritesheet_path(directories: Array, prefix: String) -> String:
	var expected_file := "%s.png" % prefix
	for directory_path_variant in directories:
		var directory_path := String(directory_path_variant)
		var dir := DirAccess.open(directory_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				var resource_name := _resource_file_name(file_name)
				if resource_name.to_lower() == expected_file.to_lower():
					dir.list_dir_end()
					return "%s/%s" % [directory_path, resource_name]
			file_name = dir.get_next()
		dir.list_dir_end()
	return ""


static func _is_animation_frame(file_name: String, prefix: String) -> bool:
	var lower_name := _resource_file_name(file_name).to_lower()
	var lower_prefix := prefix.to_lower()
	if not lower_name.ends_with(".png"):
		return false
	var base_name := lower_name.get_basename()
	return base_name.begins_with(lower_prefix + "_")


static func _resource_file_name(file_name: String) -> String:
	return file_name.trim_suffix(".import")


static func _sort_frame_paths(a: String, b: String) -> bool:
	var name_a := a.get_file()
	var name_b := b.get_file()
	var group_a := _frame_group_name(name_a)
	var group_b := _frame_group_name(name_b)
	if group_a == group_b:
		var frame_a := _extract_frame_number(name_a)
		var frame_b := _extract_frame_number(name_b)
		if frame_a == frame_b:
			return name_a < name_b
		return frame_a < frame_b
	return group_a < group_b


static func _frame_group_name(file_name: String) -> String:
	var base_name := file_name.get_basename()
	var end_index := base_name.length() - 1
	while end_index >= 0 and base_name.substr(end_index, 1).is_valid_int():
		end_index -= 1
	if end_index >= 0 and base_name.substr(end_index, 1) == "_":
		end_index -= 1
	return base_name.substr(0, end_index + 1)


static func _extract_frame_number(file_name: String) -> int:
	var base_name := file_name.get_basename()
	var digits := ""
	for index in range(base_name.length() - 1, -1, -1):
		var character := base_name.substr(index, 1)
		if character.is_valid_int():
			digits = character + digits
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 0


static func _load_normalized_texture(path: String, animation_info: Dictionary, options: Dictionary) -> Texture2D:
	var source_texture := ResourceLoader.load(path) as Texture2D
	if source_texture == null:
		return null
	var source_image := source_texture.get_image()
	if source_image == null:
		return source_texture
	return _normalize_image(source_image, animation_info, options)


static func _normalize_image(source_image: Image, animation_info: Dictionary, options: Dictionary) -> Texture2D:
	if source_image.get_format() != Image.FORMAT_RGBA8:
		source_image.convert(Image.FORMAT_RGBA8)

	var canvas_size := Vector2i(options.get("canvas_size", Vector2i(96, 96)))
	if bool(options.get("preserve_source_canvas", false)):
		if source_image.get_width() == canvas_size.x and source_image.get_height() == canvas_size.y:
			return ImageTexture.create_from_image(source_image.duplicate())

	var used_rect: Rect2i = source_image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return null

	var cropped_image: Image = source_image.get_region(used_rect)
	var target_height := int(animation_info.get("target_height", options.get("target_height", canvas_size.y - 12)))
	var max_width := int(animation_info.get("max_width", options.get("max_width", canvas_size.x - 8)))
	var foot_margin := int(animation_info.get("foot_margin", options.get("foot_margin", 4)))
	var scale_factor := float(target_height) / float(cropped_image.get_height())
	var scaled_width := maxi(1, int(round(cropped_image.get_width() * scale_factor)))
	var scaled_height := target_height
	if scaled_width > max_width:
		scale_factor = float(max_width) / float(cropped_image.get_width())
		scaled_width = max_width
		scaled_height = maxi(1, int(round(cropped_image.get_height() * scale_factor)))
	cropped_image.resize(scaled_width, scaled_height, Image.INTERPOLATE_NEAREST)

	var output_image := Image.create_empty(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	output_image.fill(Color(0, 0, 0, 0))
	var paste_position := Vector2i(
		int(round((canvas_size.x - scaled_width) * 0.5)),
		canvas_size.y - foot_margin - scaled_height
	)
	output_image.blit_rect(cropped_image, Rect2i(Vector2i.ZERO, Vector2i(scaled_width, scaled_height)), paste_position)
	return ImageTexture.create_from_image(output_image)


static func _add_spritesheet_frames(frames: SpriteFrames, animation_name: String, sheet_path: String, animation_info: Dictionary, options: Dictionary) -> bool:
	var source_texture := ResourceLoader.load(sheet_path) as Texture2D
	if source_texture == null:
		return false
	var source_image := source_texture.get_image()
	if source_image == null:
		return false
	if source_image.get_format() != Image.FORMAT_RGBA8:
		source_image.convert(Image.FORMAT_RGBA8)

	var manifest := _load_manifest(sheet_path)
	var canvas_size := Vector2i(options.get("canvas_size", Vector2i(96, 96)))
	var frame_size := _frame_size_from_manifest(manifest, canvas_size)
	if frame_size.x <= 0 or frame_size.y <= 0:
		frame_size = _infer_frame_size(source_image, canvas_size)
	var frame_count := int(manifest.get("frames", 0))
	if frame_count <= 0:
		frame_count = maxi(1, int(source_image.get_width() / frame_size.x))

	var added := 0
	for frame_index in range(frame_count):
		var x := frame_index * frame_size.x
		if x + frame_size.x > source_image.get_width():
			break
		var frame_image := source_image.get_region(Rect2i(Vector2i(x, 0), frame_size))
		var texture := _normalize_image(frame_image, animation_info, options)
		if texture == null:
			continue
		frames.add_frame(animation_name, texture)
		added += 1
	return added > 0


static func _load_manifest(sheet_path: String) -> Dictionary:
	var manifest_path := "%s.json" % sheet_path.get_basename()
	if not FileAccess.file_exists(manifest_path):
		return {}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _frame_size_from_manifest(manifest: Dictionary, _fallback_size: Vector2i) -> Vector2i:
	var frame_size_variant: Variant = manifest.get("frame_size", [])
	if typeof(frame_size_variant) == TYPE_ARRAY:
		var frame_size_array: Array = frame_size_variant
		if frame_size_array.size() >= 2:
			return Vector2i(int(frame_size_array[0]), int(frame_size_array[1]))
	return Vector2i.ZERO


static func _infer_frame_size(source_image: Image, fallback_size: Vector2i) -> Vector2i:
	if source_image.get_width() >= fallback_size.x and source_image.get_width() % fallback_size.x == 0:
		return Vector2i(fallback_size.x, mini(fallback_size.y, source_image.get_height()))
	if source_image.get_width() > source_image.get_height() and source_image.get_width() % source_image.get_height() == 0:
		return Vector2i(source_image.get_height(), source_image.get_height())
	return Vector2i(source_image.get_width(), source_image.get_height())
