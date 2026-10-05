class_name ItemSlot
extends Resource
## One stack in the grid: an [Item] and how many. In a save it also records which tab and slot it sat in.

@export var item: Item
@export var count: int = 1
@export var category: Item.Category = Item.Category.MATERIALS ## Set on save.
@export var index: int = 0 ## Set on save.


static func make(new_item: Item, new_count: int) -> ItemSlot:
	var slot: ItemSlot = ItemSlot.new()
	slot.item = new_item
	slot.count = new_count
	return slot
