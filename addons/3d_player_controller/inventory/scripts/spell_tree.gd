@tool # The editor's Spell Tree panel calls the grid methods below; without tool mode the resource is a placeholder there
class_name SpellTree
extends Resource
## A tree of [SpellNode]s the [Spellbook] unlocks through: each node names its ability, its cost in skill points,
## its prerequisites and its row and column on the [SpellsScreen] grid. A project can ship several trees and
## point a Player's Spellbook at one. The grid is laid out here, once, so the Spells screen and the editor's Spell
## Tree panel draw the same picture: [constant CELL] pixels per column and row, and a prerequisite drawn by
## [method draw_connection] as a straight line between the two spells' edges with an arrow at its middle pointing
## at the spell that comes later, the way the AnimationTree draws a transition.

const CELL: Vector2 = Vector2(112.0, 120.0) ## One grid cell in pixels; a node sits at [method cell_position].
const ARROW_SIZE: float = 3.0 ## The arrowhead's half-length, in line widths.

@export var display_name: String = "Spells"
@export var nodes: Array[SpellNode] = []


## Where [param node] sits on the grid, in pixels: its column and row in cells.
static func cell_position(node: SpellNode) -> Vector2:
	return Vector2(node.column, node.row) * CELL


## The grid's size in pixels: every column and row, in cells.
func pixel_size() -> Vector2:
	return Vector2(column_count(), row_count()) * CELL


## The straight line from a prerequisite to a dependent, centre to centre but trimmed to each one's edge, as
## [code][start, end][/code]. Two spells at the same spot give a zero-length line.
static func connection_segment(from_rect: Rect2, to_rect: Rect2) -> PackedVector2Array:
	var direction: Vector2 = to_rect.get_center() - from_rect.get_center()
	if direction.is_zero_approx():
		return PackedVector2Array([from_rect.get_center(), to_rect.get_center()])
	direction = direction.normalized()
	return PackedVector2Array([_edge_point(from_rect, direction), _edge_point(to_rect, -direction)])


## Draws the prerequisite line on [param item] with an arrowhead at its middle pointing at the dependent.
static func draw_connection(item: CanvasItem, from_rect: Rect2, to_rect: Rect2, color: Color, width: float = 3.0) -> void:
	var segment: PackedVector2Array = connection_segment(from_rect, to_rect)
	var direction: Vector2 = segment[1] - segment[0]
	if direction.is_zero_approx():
		return
	item.draw_line(segment[0], segment[1], color, width, true)
	direction = direction.normalized()
	var middle: Vector2 = (segment[0] + segment[1]) * 0.5
	var reach: Vector2 = direction * width * ARROW_SIZE
	var side: Vector2 = direction.orthogonal() * width * ARROW_SIZE * 0.7
	item.draw_colored_polygon(PackedVector2Array([middle + reach, middle - reach + side, middle - reach - side]), color)


## Where a ray from [param rect]'s centre along [param direction] leaves it.
static func _edge_point(rect: Rect2, direction: Vector2) -> Vector2:
	var half: Vector2 = rect.size * 0.5
	var distance: float = INF
	if not is_zero_approx(direction.x):
		distance = minf(distance, half.x / absf(direction.x))
	if not is_zero_approx(direction.y):
		distance = minf(distance, half.y / absf(direction.y))
	return rect.get_center() + direction * distance


## The node that unlocks [param ability], or null when the tree does not have it.
func get_node_for(ability: Ability) -> SpellNode:
	for node: SpellNode in nodes:
		if node.ability == ability:
			return node
	return null


func has(ability: Ability) -> bool:
	return get_node_for(ability) != null


## Rows on the grid (the deepest node's row plus one).
func row_count() -> int:
	var rows: int = 0
	for node: SpellNode in nodes:
		rows = maxi(rows, node.row + 1)
	return rows


## Columns on the grid (the rightmost node's column plus one).
func column_count() -> int:
	var columns: int = 0
	for node: SpellNode in nodes:
		columns = maxi(columns, node.column + 1)
	return columns


## The node at a grid cell, or null.
func get_node_at(row: int, column: int) -> SpellNode:
	for node: SpellNode in nodes:
		if node.row == row and node.column == column:
			return node
	return null
