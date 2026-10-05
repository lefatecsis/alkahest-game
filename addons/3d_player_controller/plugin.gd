# Copyright (c) 2026 Antigravity Contributors
# SPDX-License-Identifier: MIT

@tool
extends EditorPlugin

## 3D Player Controller plugin editor integration.
##
## The inventory's editor tooling lives here too. Godot only reads plugin.cfg one level under addons/, so
## with the inventory at addons/3d_player_controller/inventory/ a plugin.cfg of its own is never seen and its Spell Tree
## editor would simply not appear. Rather than leave it unreachable, its behaviour is merged in: the
## bottom panel opens whenever a SpellTree resource is selected, the way AnimationTree opens its own.
##
## The inventory registers no custom types; Inventory, InventoryScreen, ItemPickup, Item and the save resources
## carry class_name and icons of their own.

const SPELL_TREE_EDITOR: GDScript = preload("res://addons/3d_player_controller/inventory/editor/spell_tree_editor.gd")

var editor: SpellTreeEditor
var panel_button: Button
var save_dialog: EditorFileDialog


func _enter_tree() -> void:
	add_custom_type(
		"Player",
		"CharacterBody3D",
		preload("res://addons/3d_player_controller/scripts/player.gd"),
		null
	)

	editor = SPELL_TREE_EDITOR.new()
	editor.undo_redo = get_undo_redo()
	editor.ui_scale = EditorInterface.get_editor_scale()
	editor.save_as_requested.connect(_on_save_as_requested)
	editor.saved.connect(_on_saved)
	panel_button = add_control_to_bottom_panel(editor, "Spell Tree")
	panel_button.hide()
	save_dialog = EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	save_dialog.filters = PackedStringArray(["*.tres ; Spell Tree"])
	save_dialog.title = "Save Spell Tree As"
	save_dialog.file_selected.connect(editor.save_to)
	EditorInterface.get_base_control().add_child(save_dialog)


func _exit_tree() -> void:
	remove_custom_type("Player")
	if is_instance_valid(editor):
		remove_control_from_bottom_panel(editor)
		editor.queue_free()
	if is_instance_valid(save_dialog):
		save_dialog.queue_free()


func _handles(object: Object) -> bool:
	return object is SpellTree


func _edit(object: Object) -> void:
	if is_instance_valid(editor):
		editor.set_tree(object as SpellTree)


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(editor):
		return
	if visible:
		panel_button.show()
		editor.ensure_palette()
		make_bottom_panel_item_visible(editor)
	else:
		if editor.visible:
			hide_bottom_panel()
		panel_button.hide()


func _on_save_as_requested(_tree: SpellTree) -> void:
	save_dialog.current_dir = "res://resources/spells" if DirAccess.dir_exists_absolute("res://resources/spells") else "res://"
	save_dialog.popup_file_dialog()


func _on_saved(path: String) -> void:
	EditorInterface.get_resource_filesystem().update_file(path)
