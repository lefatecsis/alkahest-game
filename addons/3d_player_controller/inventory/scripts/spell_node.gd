class_name SpellNode
extends Resource
## One entry of a [SpellTree]: the [Ability] it unlocks, what it costs, what must be unlocked first and where it
## sits on the tree's grid.

@export var ability: Ability
@export_range(0, 99) var cost: int = 1 ## Skill points to unlock; 0 is free.
@export var requires: Array[Ability] = [] ## Every one of these must be unlocked first.
@export_range(0, 32) var row: int = 0 ## Top to bottom.
@export_range(0, 32) var column: int = 0 ## Left to right.
