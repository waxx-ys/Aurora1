extends Node
func _ready() -> void:
	var menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(4.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://docs/menu_preview.png"))
	print("saved")
	get_tree().quit()
