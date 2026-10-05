class_name Accuracy
extends Resource
## How far a round can stray from the aim line: a cone per weapon that shrinks with the shooter's skill.
## Save one as a .tres per weapon (see resources/accuracy/) and tune it in the editor; the shooter
## (Player or EnemyNpc) supplies its [code]skill_level[/code].

@export_range(0.0, 45.0, 0.05, "degrees") var spread_degrees: float = 4.0 ## Cone half-angle for an unskilled shooter (skill level 0).
@export_range(0.0, 45.0, 0.05, "degrees") var expert_spread_degrees: float = 0.25 ## Cone half-angle at [member expert_level] and above.
@export_range(1, 100) var expert_level: int = 10 ## The skill level where the spread stops shrinking.


## The cone half-angle in degrees for [param skill_level], eased linearly between novice and expert.
func spread_for(skill_level: int) -> float:
	return lerpf(spread_degrees, expert_spread_degrees, clampf(float(skill_level) / float(expert_level), 0.0, 1.0))


## [param direction] pushed a random amount off its line, inside the cone for [param skill_level].
## The stray angle is uniform, so most rounds land near the centre.
func scatter(direction: Vector3, skill_level: int) -> Vector3:
	var along: Vector3 = direction.normalized()
	var spread: float = spread_for(skill_level)
	if spread <= 0.0 or along.is_zero_approx():
		return along
	var side: Vector3 = along.cross(Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT).normalized()
	return along.rotated(side, deg_to_rad(randf() * spread)).rotated(along, randf() * TAU)
