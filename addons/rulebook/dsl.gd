class_name Dsl
extends RefCounted
## Rulebook: the rule language - lifted from Drillbook Bots' drill.gd and made game-agnostic.
## A game registers pattern tables (conditions, actions); Dsl parses and runs rules against them. A rule is `when <condition> -> <action>; <action>` or `otherwise -> ...`.
## Conditions combine with and / or / not / parentheses and `<condition> for 2s` (held that long).
##
## Pattern slots: #D yards ("m" or "metres" converted), #P percent (70% or 0.7), #S seconds,
## #X number, $W one word, $R the rest of the atom (quoted names keep their spaces).

const METRE := 1.0936


static func strip_comment(line: String) -> String:
	# a '#' starts a comment, unless it is inside quotes
	var q := false
	for i in line.length():
		var c := line[i]
		if c == "\"":
			q = not q
		elif c == "#" and not q:
			return line.substr(0, i)
	return line


static func quoted(s: String) -> String:
	s = s.strip_edges()
	if s.begins_with("\"") and s.ends_with("\"") and s.length() >= 2:
		return s.substr(1, s.length() - 2)
	return s


## Every "quoted name" in a string, in order.
static func names_in(s: String) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while true:
		var a := s.find("\"", i)
		if a < 0:
			break
		var b := s.find("\"", a + 1)
		if b < 0:
			break
		out.append(s.substr(a + 1, b - a - 1))
		i = b + 1
	return out


static func tokenize(s: String) -> Array:
	var out := []
	var cur := ""
	var q := false
	for ch in s:
		if q:
			cur += ch
			if ch == "\"":
				q = false
				out.append(cur)
				cur = ""
			continue
		if ch == "\"":
			if cur != "":
				out.append(cur)
			cur = "\""
			q = true
		elif ch == "(" or ch == ")":
			if cur != "":
				out.append(cur)
				cur = ""
			out.append(ch)
		elif ch == " " or ch == "\t" or ch == ",":
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


## Parse one rule line (already lower-cased outside quotes). Returns {cond, actions, line} or {}
## with errors appended.
static func parse_rule(text: String, ln: int, conditions: Array, actions_table: Array, errors: Array, who: String) -> Dictionary:
	var arrow := text.find("->")
	if arrow < 0:
		errors.append("line %d: a rule needs '->' between the condition and what to do" % ln)
		return {}
	var cond_s := text.substr(0, arrow).strip_edges()
	var act_s := text.substr(arrow + 2).strip_edges()
	var cond: Variant = true
	if cond_s.begins_with("when "):
		var toks := tokenize(cond_s.substr(5))
		var pos := [0]
		cond = _parse_or(toks, pos, ln, conditions, errors)
		if pos[0] < toks.size():
			errors.append("line %d: can't read the condition from '%s'" % [ln, " ".join(toks.slice(pos[0]))])
	elif not cond_s.begins_with("otherwise"):
		errors.append("line %d: a rule starts with 'when' or 'otherwise'" % ln)
		return {}
	var acts: Array = []
	for part in _split_actions(act_s):
		var toks := tokenize(part)
		if not toks.is_empty() and toks[0] == "then":
			toks = toks.slice(1)
		if toks.is_empty():
			continue
		var m := match_tokens(toks, actions_table)
		if m.is_empty():
			errors.append("line %d: '%s' is not something a %s can do%s" % [ln, " ".join(toks), who, RuleHelp.did_you_mean(toks, actions_table)])
			continue
		acts.append(m)
	if acts.is_empty():
		return {}
	return {"cond": cond, "actions": acts, "line": ln}


static func _split_actions(s: String) -> Array:
	var out := []
	var cur := ""
	var q := false
	for ch in s:
		if ch == "\"":
			q = not q
		if ch == ";" and not q:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	out.append(cur)
	return out


## Lower-case a line except inside quotes (names keep their capitals).
static func lower_outside_quotes(s: String) -> String:
	var out := ""
	var q := false
	for ch in s:
		if ch == "\"":
			q = not q
			out += ch
		elif q:
			out += ch
		else:
			out += ch.to_lower()
	return out


static func _parse_or(toks: Array, pos: Array, ln: int, table: Array, errors: Array) -> Variant:
	var left: Variant = _parse_and(toks, pos, ln, table, errors)
	while pos[0] < toks.size() and toks[pos[0]] == "or":
		pos[0] += 1
		left = ["or", left, _parse_and(toks, pos, ln, table, errors)]
	return left


static func _parse_and(toks: Array, pos: Array, ln: int, table: Array, errors: Array) -> Variant:
	var left: Variant = _parse_not(toks, pos, ln, table, errors)
	while pos[0] < toks.size() and toks[pos[0]] == "and":
		pos[0] += 1
		left = ["and", left, _parse_not(toks, pos, ln, table, errors)]
	return left


static func _parse_not(toks: Array, pos: Array, ln: int, table: Array, errors: Array) -> Variant:
	if pos[0] < toks.size() and toks[pos[0]] == "not":
		pos[0] += 1
		return ["not", _parse_not(toks, pos, ln, table, errors)]
	if pos[0] < toks.size() and toks[pos[0]] == "(":
		pos[0] += 1
		var inner: Variant = _parse_or(toks, pos, ln, table, errors)
		if pos[0] < toks.size() and toks[pos[0]] == ")":
			pos[0] += 1
		else:
			errors.append("line %d: a '(' without its ')'" % ln)
		# "(a or b) for 2s": the whole group must have held that long
		if pos[0] + 1 < toks.size() and toks[pos[0]] == "for" and _is_seconds(toks[pos[0] + 1]):
			var held := num(toks[pos[0] + 1])
			pos[0] += 2
			return ["for", inner, held, "%d:group%d" % [ln, pos[0]]]
		return inner
	var atom := []
	while pos[0] < toks.size() and not ["and", "or", ")"].has(toks[pos[0]]):
		atom.append(toks[pos[0]])
		pos[0] += 1
	if atom.is_empty():
		errors.append("line %d: a condition is missing" % ln)
		return false
	var held := -1.0
	if atom.size() >= 3 and atom[atom.size() - 2] == "for" and _is_seconds(atom[atom.size() - 1]):
		held = num(atom[atom.size() - 1])
		atom = atom.slice(0, atom.size() - 2)
	var m := match_tokens(atom, table)
	if m.is_empty():
		errors.append("line %d: don't know the condition '%s'%s" % [ln, " ".join(atom), RuleHelp.did_you_mean(atom, table)])
		return false
	if held >= 0.0:
		return ["for", m, held, "%d:%s" % [ln, " ".join(atom)]]
	return m


static func _is_seconds(tok: String) -> bool:
	return tok.ends_with("s") and tok.substr(0, tok.length() - 1).is_valid_float()


static func num(tok: String) -> float:
	var t := tok
	for suf in ["yd", "m", "s", "%"]:
		if t.ends_with(suf):
			t = t.substr(0, t.length() - suf.length())
			break
	return float(t)


static func num_ok(tok: String) -> bool:
	var t := tok
	for suf in ["yd", "m", "s", "%"]:
		if t.ends_with(suf):
			t = t.substr(0, t.length() - suf.length())
			break
	return t.is_valid_float()


## Match tokens against a pattern table; the first pattern that consumes every token wins.
static func match_tokens(toks: Array, table: Array) -> Dictionary:
	for entry in table:
		var pat: Array = entry[0]
		var args := []
		var i := 0
		var ok := true
		for p in pat:
			if i >= toks.size():
				ok = false
				break
			var tok: String = toks[i]
			if p == "#D":
				if not num_ok(tok):
					ok = false
					break
				var v := num(tok)
				if tok.ends_with("m") and not tok.ends_with("yd"):
					v *= METRE
				i += 1
				if i < toks.size() and toks[i] in ["yards", "yard", "yds", "yd"]:
					i += 1
				elif i < toks.size() and toks[i] in ["m", "metres", "meters"]:
					v *= METRE
					i += 1
				args.append(v)
			elif p == "#P":
				if not num_ok(tok):
					ok = false
					break
				var v := num(tok)
				if tok.ends_with("%") or v > 1.0:
					v /= 100.0
				args.append(v)
				i += 1
				if i < toks.size() and toks[i] == "percent":
					i += 1
			elif p == "#S" or p == "#X":
				if not num_ok(tok):
					ok = false
					break
				args.append(num(tok))
				i += 1
				if p == "#S" and i < toks.size() and toks[i] in ["seconds", "second", "sec", "secs"]:
					i += 1
			elif p == "$W":
				args.append(quoted(tok))
				i += 1
			elif p == "$R":
				args.append(" ".join(toks.slice(i)))
				i = toks.size()
			else:
				if tok != p:
					ok = false
					break
				i += 1
		if ok and i == toks.size():
			return {"id": entry[1], "args": args}
	return {}


## Run a rule list. `sense(id, args)` answers a condition; `act(id, args)` tries an action and
## says whether it could be done. Actions in `modifiers` don't end the evaluation. Returns the
## line of the rule that decided, or -1.
static func run(rules: Array, sense: Callable, act: Callable, memory: Dictionary, now: float, modifiers: Array, tally: Dictionary) -> int:
	for r in rules:
		if not eval(r["cond"], sense, memory, now):
			continue
		var decided := false
		var any := false
		for a in r["actions"]:
			var done: bool = act.call(a["id"], a["args"])
			if done:
				any = true
				if not modifiers.has(a["id"]):
					decided = true
		if any:
			tally[r["line"]] = int(tally.get(r["line"], 0)) + 1
		if decided:
			return int(r["line"])
	return -1


static func eval(c: Variant, sense: Callable, memory: Dictionary, now: float) -> bool:
	if c is bool:
		return c
	if c is Dictionary:
		return sense.call(c["id"], c["args"])
	var op: String = c[0]
	match op:
		"and":
			return eval(c[1], sense, memory, now) and eval(c[2], sense, memory, now)
		"or":
			return eval(c[1], sense, memory, now) or eval(c[2], sense, memory, now)
		"not":
			return not eval(c[1], sense, memory, now)
		"for":
			var key: String = c[3]
			if eval(c[1], sense, memory, now):
				if not memory.has(key):
					memory[key] = now
				return now - float(memory[key]) >= float(c[2])
			memory.erase(key)
			return false
	return false
