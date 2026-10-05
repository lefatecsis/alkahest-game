# The inventory's contract with the 3D Player Controller

Everything the inventory (`addons/3d_player_controller/inventory/`: scripts, scenes, resources and the tests in `tests/`)
touches on the rest of the player controller. It used to be its own addon and this table was what its stub had
to implement; now that it ships as a subfolder the table is a boundary rather than a build requirement, and it
earns its keep by keeping the subfolder liftable instead of letting it grow into everything around it.
`tests/integration/` reaches past this surface deliberately and is not covered by it. Anything not listed here is
not the inventory's to use; widen the table before widening the code.

## Player (`scripts/player.gd`, `class_name Player extends CharacterBody3D`)

| Member | Type | Needed for |
|---|---|---|
| `controls` | `CanvasLayer` (a `Controls`) | `Inventory.rebuild_equipment_cache` calls `reset_labels()`; `InventoryScreen`, `SpellsScreen` and `RadialMenu` read `current_input_type` |
| `crosshair` | `TextureRect` | `RadialMenu` hides it while the wheel is open and shows it after |
| `inventory` | `Inventory` | `ItemPickup.take` (`inventory.room_for`, then `add_item` once the server grants), `InventoryScreen.bind`, `SpellsScreen.bind`, `Equipment.equip` and the walk-over pickups (`inventory.equip_pickup`), the demo |
| `abilities` | `Abilities` | `Spellbook._apply` writes the wheel, `SpellsScreen.refresh` reads `active_ability` |
| `radial_menu` | `RadialMenu` (`$Hud/Inventory/RadialMenu`) | The tests reach the weapon wheel through it |
| `pause` | `PlayerMenuLayer` | The screens' Back button calls `pause.show_menu()` |
| `skeleton` | `Skeleton3D` | `Inventory.equip_pickup` adds a `BoneAttachment3D` under it; `Inventory.equip_from_backpack` reparents attachments onto it; `apply_save` checks it is there |
| `held_object` | `HeldObject` | `Inventory._unhandled_input` ignores weapon taps while `is_holding_object()` |
| `is_paused` | `bool` | `ItemPickup._input` ignores Action while paused; `PlayerMenuLayer.show_menu` / `hide_menu` set it |
| `is_riding` | `bool` | `ItemPickup` ignores a riding Player |
| `ready` | signal (Node) | `Spellbook._ready` waits for the Player before seeding the wheel |
| `get_facing_direction()` | `-> Vector3` | `Inventory._drop` drops pickups a metre ahead (`Vector3.ZERO` falls back to forward) |
| `get_path()` | native | `Inventory._drop` names the dropper to the `ProjectileSpawner` (its "shooter"); `ItemPickup` names the taker to the server by its path from the pickup |
| `warp_to(target)` | `(Transform3D) -> void` | Tests move the Player onto and off dropped equipment |
| native | `is_multiplayer_authority()`, `get_multiplayer_authority()`, `up_direction`, `global_position`, `get_parent()`, `is_node_ready()` | `Inventory`, `ItemPickup` (the server grants a take only to the Player's own peer), `Spellbook` |

## SaveGame (`scripts/save_game.gd`, `class_name SaveGame extends Node`)

| Member | Type | Needed for |
|---|---|---|
| `to_plain(value)` | `static (Variant) -> Variant` | `Inventory.save` turns its `InventorySave` into plain JSON: a `res://` resource becomes its path, a run-time one its script's path and stored properties |
| `from_plain(value)` | `static (Variant) -> Variant` | `Inventory.load_save` and `test_spellbook.gd` read it back; a path that is gone comes back null, so a missing item is skipped |

## Controls (`scripts/controls.gd`, `class_name Controls extends CanvasLayer`)

| Member | Type | Needed for |
|---|---|---|
| `InputType` | enum `KEYBOARD_MOUSE, MICROSOFT, NINTENDO, SONY, TOUCH` | `current_input_type` values |
| `current_input_type` | `InputType` (default `TOUCH`) | `KEYBOARD_MOUSE` puts a held stack or spell under the mouse instead of the focused cell; the wheel reads the mouse or the right stick |
| `reset_labels()` | `-> void` | Restores every label's scene text; called after the equipped set changes |
| Actions it listens for | `action`, `start`, `ability`, `throw`, `last_weapon`, `next_weapon`, `look_up/down/left/right` | The player controller registers them in the InputMap at runtime; the inventory only presses and reads them (the built in `ui_accept` and `ui_cancel` are used as they are). The tests in `tests/` add any the project lacks themselves (`tests/contract_actions.gd`, in `before_all`) and take those back out in `after_all`, so they do not depend on a Controls node having readied first |

## HeldObject (`scripts/held_object.gd`, `class_name HeldObject extends Node`)

| Member | Type | Needed for |
|---|---|---|
| `is_holding_object()` | `-> bool` | Weapon taps do nothing while an object is carried |

## PlayerMenuLayer (`scripts/player_menu_layer.gd`, `class_name PlayerMenuLayer extends CanvasLayer`)

`InventoryScreen` and `SpellsScreen` extend it.

| Member | Type | Needed for |
|---|---|---|
| `player` | `@export Player` | The screens bind to `player.inventory`; whoever instances a screen sets it |
| `focus_on_show` | `@export Control` | Focused by `show_menu`; the screens leave it empty and focus a slot themselves |
| `_ready()` | | `set_process_input(is_multiplayer_authority())` then `fit_touch_buttons(self)` |
| `fit_touch_buttons(root)` | `static (Node) -> void` | Duplicates each `TouchScreenButton`'s `RectangleShape2D`, sizes it to the parent `Control` and centres it, now and on the control's `resized`; `InventorySlotButton` and `SpellNodeButton` call it on themselves |
| `_input(event)` | | `start` while visible calls `hide_menu()` and marks the event handled |
| `show_menu()` | `-> void` | Shows, sets `player.is_paused = true`, frees the mouse, focuses `focus_on_show` |
| `hide_menu()` | `-> void` | Hides, sets `player.is_paused = false`, captures the mouse |

## Pause (`scenes/ui/pause.tscn`, a `PlayerMenuLayer` at `player.pause`)

| Member | Type | Needed for |
|---|---|---|
| `show_menu()` | inherited | The screens' Back hides the screen and calls `player.pause.show_menu()`; the tests check `player.pause.visible` and call `hide_menu()` |

How Pause opens the screens is the player controller's use of the inventory, not the inventory's of the player controller: the real
`pause.gd` has `inventory_screen_scene` and `spells_screen_scene` exports that `player.tscn` points at the inventory's
screens, instances them beside itself on the Player with `player` set, and shows an Inventory and a Spells button
that hide Pause and `show_menu()` the screen. That flow is covered only in `tests/integration/test_pause_menu_flow.gd`, since it
is the one direction of the coupling this table does not govern.

## ActionPrompt (`scripts/action_prompt.gd`, `class_name ActionPrompt extends Node3D`, scene `scenes/action_prompt.tscn`)

`item_pickup.tscn` instances the scene as `ActionPrompt` and sets `message_end`. What the prompt does with the
Player's controls (naming the Action button while it is up, handing the label back to the Player's state when it
hides) is behind `show_for` / `hide_for` and is the player controller's; the contract tier never reads a label.

| Member | Type | Needed for |
|---|---|---|
| `message_end` | `@export String` | "to pick up", set in `item_pickup.tscn`; the prompt puts it on its labels itself |
| `show_for(player, action_label)` | `(Player, String) -> void` | Shows the prompt for the Player's input type; `ItemPickup` passes "Pick Up" |
| `hide_for(player)` | `(Player) -> void` | Hides it, walking away or once the stack is taken |
| `visible` | `bool` | Tests check the prompt is up or down |

## Abilities (`scripts/abilities.gd`, `class_name Abilities extends CanvasLayer`)

| Member | Type | Needed for |
|---|---|---|
| `player` | `@export Player` | `player.tscn` wires it |
| `abilities` | `@export Array[Ability]` | The wheel; `Spellbook._seed` reads the starting spells from it and `_apply` writes the loadout to it |
| `active_ability` | `@export Ability` | The first of `abilities` at ready; `Spellbook._apply` keeps it on the wheel; `SpellsScreen` marks the slot that holds it |

## Ability (`scripts/ability.gd`, `class_name Ability extends Resource`)

| Member | Type | Needed for |
|---|---|---|
| `display_name` | `@export String` | Node buttons, details, wheel slots, palette labels, button names |
| `icon` | `@export Texture2D` | Node buttons, details, wheel slots, the held icon, the palette |
| `icon_color` | `@export Color` | Tints the icon everywhere it is drawn |
| `get_details()` | `-> String`, optional | The details panel's `DetailInfo` line (damage, ticks, slows); `SpellsScreen` checks `has_method` first, so an ability need not have it |
| `HealAbility` | `scripts/heal_ability.gd extends Ability` | `heal.tres` (`script_class="HealAbility"`); the editor's class chain test |
| `StealthAbility` | `scripts/stealth_ability.gd extends Ability` | `stealth.tres` (`script_class="StealthAbility"`); the editor's class chain test |

Abilities carry cooldowns, cast times, costs, cast styles and audio as well; the inventory saves the resource rather than
the fields, so only the three above are its business.

## Equipment (`scripts/equipment.gd`, `class_name Equipment extends Node3D`)

The attach itself is the inventory's: `Inventory.equip_pickup(pickup)` makes the `BoneAttachment3D` on `player.skeleton`,
duplicates the pickup onto it with `scene_file_path` copied and `player` set, disables every collision shape but a
"Hitbox"'s, starts any `AnimationTree`, applies the offsets (from a pickup in the tree) and adds the copy. The real
`Equipment.equip(player)` calls it and keeps the copy as its own `equipment_instance`; the inventory never reads that.

| Member | Type | Needed for |
|---|---|---|
| `EquipmentType` | enum `AXE_1H, AXE_2H, BOW, DAGGER, FISHING_ROD, PISTOL, RIFLE, STAFF, SWORD_1H, SWORD_2H, SWORD_AND_SHIELD` | Order matters: `Inventory` sorts and looks up by it, `wooden_sword.tscn` stores `8` |
| `bone_attachment_bone_name` | `@export String` | Backpack conflicts, sorting, the attachment's bone |
| `can_attack`, `can_shoot` | `@export bool` | `can_player_attack` / `can_player_shoot` |
| `can_log`, `can_mine` | `@export bool` | `has_equipment_with_capability(&"can_log")` reads them by name |
| `display_name`, `description` | `@export String` | Slot tooltips, the wheel, the details panel |
| `model_scene` | `@export PackedScene` | The details panel's turning preview |
| `equipment_type` | `@export EquipmentType` | Lookup and sorting |
| `icon` | `@export Texture2D` | Slots and the wheel |
| `is_exclusive` | `@export bool` | `stow_conflicting` |
| `position_offset`, `rotation_offset_degrees`, `scale_offset` | `@export Vector3` | `wooden_sword.tscn` sets them; `equip_pickup` applies them to the copy |
| `player` | `Player` | `equip_pickup` sets it on the copy |
| `get_details()` | `-> String` | Extra lines under the description |
| `details_changed` | signal | The inventory screen redraws an equipment entry whose details changed while it is open (the fishing rod emits it when its bait changes) |
| `_on_player_detection_body_entered(body)` | `(Node3D) -> void` | Wired in `wooden_sword.tscn` from a child `Area3D` named `PlayerDetection`: hands the pickup to the first authoritative Player's `inventory.equip_pickup` unless the pickup's `dropped_by` meta is that Player, then vanishes on every peer |
| `set_dropped_by(dropper)` | `(Node3D) -> void` | `Inventory._spawn_dropped` (and the `ProjectileSpawner` building a drop) mark the Player who dropped it; the pickup clears the mark itself on its area's `body_exited` |
| `scene_file_path` | native | `origin_of` (a `.tscn` or `.scn` names the piece), `drop_equipment` and `_is_scene_path` |
| `origin` meta | `String` | Set by `equip_pickup` on a copy of a world pickup: the pickup's node path, what `origin_of` names a piece by when it has no scene of its own (saves, peers, drops) |

## ProjectileSpawner (`scripts/projectile_spawner.gd`, `class_name ProjectileSpawner extends MultiplayerSpawner`)

Optional: without one in the world, drops land by the inventory's own RPC and pickups work as before; with one, a drop
comes through it, so a peer joining later gets it too.

| Member | Type | Needed for |
|---|---|---|
| `find_for(node)` | `static (Node) -> ProjectileSpawner` | `Inventory._drop` looks for the spawner of its session |
| `place(scene, position, extra)` | `(PackedScene, Vector3, Dictionary) -> Node3D` | `Inventory._drop`: `extra` carries "shooter" (the dropping Player's path), "item" and "count" for an `ItemPickup`, or "world_pickup" (a world pickup's path, with a null scene) for a copy of it; returns the pickup on the server, null on a client |
| Spawnable scenes | inspector | A client's drop is spawned only for a scene on the list, so the world lists `item_pickup.tscn` and every droppable equipment scene |

The spawner calls back into the inventory for one thing: `Inventory.pickup_from(origin, from)` builds the copy of a world
pickup a drop names by "world_pickup"; it sets an `ItemPickup`'s `item` and `count`, and marks what it builds `spawned` (`ItemPickup.spawned`,
`Equipment.spawned`), so an emptied or taken one is left for the server to free on every peer. `item_pickup.gd` names no
`ProjectileSpawner` itself: the spawner loads the inventory, which preloads `item_pickup.tscn`, so a reference back would
make that scene load itself half way through.

## Files the inventory loads by path

| Path | Used by |
|---|---|
| `scenes/player.tscn` | `demo.tscn`, every test; see the layout below |
| `scenes/action_prompt.tscn` | `item_pickup.tscn` |
| `scripts/equipment.gd` | `scenes/demo/wooden_sword.tscn` |
| `scripts/ability.gd` (`uid://klxo6bc3ftnp`) | `resources/spell_tree_demo.tres` typed array |
| `resources/abilities/heal.tres` (`uid://cfpp5cv2gcskg`) | `spell_tree_demo.tres`, `player.tscn`, tests |
| `resources/abilities/stealth.tres` (`uid://ywtv6gwnislu`) | `spell_tree_demo.tres`, `player.tscn`, tests |
| `assets/game_icons/gladius.svg` | `inventory_screen.tscn` tab, `wooden_sword.tscn`, `wooden_sword.tres` |
| `assets/game_icons/punch.svg` | `RadialMenu.PUNCH_ICON` |
| `assets/icons/heal.svg`, `assets/game_icons/cloak-dagger.svg` | The two ability resources' icons |

## `player.tscn` layout the inventory relies on

| Node | What the inventory needs |
|---|---|
| `Player` (`CharacterBody3D`, group `Player`) | `player.gd`; a collision shape so `Area3D` pickups see it |
| `PlayerModel/Armature/GeneralSkeleton` (`Skeleton3D`) | `player.skeleton`, with the bones equipment names (`RightHand`, `LeftHand`) |
| `Hud/Controls` | `player.controls` |
| `Hud/Inventory` (`res://addons/3d_player_controller/inventory/scenes/inventory.tscn`, `player` set) | `player.inventory`, `$Hud/Inventory/RadialMenu`, `$Hud/Inventory/Spellbook` |
| `Hud/Abilities` (`player` set, `abilities = [stealth.tres, heal.tres]`) | `player.abilities`; the starting spells the Spellbook seeds from |
| `Hud/Pause` (`player` set) | `player.pause`; the real one also points its screen paths at the inventory's screens, see Pause |
| `Hud/Crosshair` (`TextureRect`) | `player.crosshair` |
| `HeldObject` | `player.held_object` |
