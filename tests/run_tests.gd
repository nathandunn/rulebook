extends SceneTree
## godot --headless --path . -s tests/run_tests.gd

const CONDITIONS := [
	[["always"], "always"],
	[["enemy", "within", "#D"], "enemy_within"],
	[["health", "under", "#P"], "health_under"],
	[["time", "over", "#S"], "time_over"],
	[["mode", "is", "$W"], "mode_is"],
]
const ACTIONS := [
	[["attack"], "attack"],
	[["flee", "#D"], "flee"],
	[["shout"], "shout"],
	[["call", "$R"], "call"],
]

var fails := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)


func _init() -> void:
	var errs: Array = []
	var r := Dsl.parse_rule("when enemy within 5 yards and not health under 30% -> attack; shout", 1, CONDITIONS, ACTIONS, errs, "guard")
	check(errs.is_empty() and r["actions"].size() == 2, "parses a rule with and/not and two actions")
	var r2 := Dsl.parse_rule("when (health under 0.3 or enemy within 2m) for 1.5s -> flee 10", 2, CONDITIONS, ACTIONS, errs, "guard")
	check(errs.is_empty() and r2["cond"] is Array and r2["cond"][0] == "for", "parentheses, metres and 'for Ns'")
	var bad: Array = []
	Dsl.parse_rule("when enemy withn 5 -> atack", 3, CONDITIONS, ACTIONS, bad, "guard")
	check(bad.size() == 2 and String(bad[0]).find("did you mean 'enemy within N'") > 0, "did you mean (condition): %s" % [bad[0] if bad.size() > 0 else ""])
	check(bad.size() == 2 and String(bad[1]).find("'attack'") > 0, "did you mean (action): %s" % [bad[1] if bad.size() > 1 else ""])
	var c := Dsl.parse_rule("otherwise -> call \"Plan B\" or \"Plan C\"", 4, CONDITIONS, ACTIONS, errs, "guard")
	check(Dsl.names_in(String(c["actions"][0]["args"][0])) == ["Plan B", "Plan C"], "quoted names keep their spaces")
	# running
	var world := {"enemy": 3.0, "health": 0.5}
	var sense := func(id: String, a: Array) -> bool:
		match id:
			"enemy_within": return world["enemy"] < a[0]
			"health_under": return world["health"] < a[0]
			"always": return true
		return false
	var did := []
	var act := func(id: String, a: Array) -> bool:
		did.append(id)
		return true
	var tally := {}
	var line := Dsl.run([r, r2], sense, act, {}, 0.0, ["shout"], tally)
	check(line == 1 and did == ["attack", "shout"], "first rule that holds decides")
	world["health"] = 0.1
	did.clear()
	var mem := {}
	line = Dsl.run([r2], sense, act, mem, 0.0, [], tally)
	check(line == -1, "'for 1.5s' not yet held")
	line = Dsl.run([r2], sense, act, mem, 2.0, [], tally)
	check(line == 2 and did == ["flee"], "'for 1.5s' held")
	# help
	check(RuleHelp.complete("enemy", CONDITIONS) == ["enemy within N"], "completion")
	check(RuleHelp.example(CONDITIONS[2][0]) == "health under 40%", "example from a pattern")
	print("%d failed" % fails)
	quit(1 if fails > 0 else 0)
