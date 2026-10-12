class_name RuleHelp
extends RefCounted
## Help for people writing rules: the vocabulary as readable phrases, a worked example for
## every phrase, "did you mean" for a word the parser doesn't know, and completions for a
## half-typed line.

## Sample values used to turn a pattern into an example.
const SAMPLE := {"#D": "5", "#P": "40%", "#S": "2s", "#X": "3", "$W": "WORD", "$R": "\"Name\""}
## What a slot means, for the cheat sheet.
const SLOT_HELP := {"#D": "yards", "#P": "percent", "#S": "seconds", "#X": "a number", "$W": "a word", "$R": "a quoted name"}


## Each distinct phrase of a table once: {phrase, id, slots}.
static func phrases(table: Array) -> Array:
	var seen := {}
	var out := []
	for e in table:
		var words := []
		var slots := []
		for p in e[0]:
			if SLOT_HELP.has(p):
				words.append({"#D": "N", "#P": "N%", "#S": "Ns", "#X": "N", "$W": "WORD", "$R": "\"NAME\""}[p])
				slots.append(p)
			else:
				words.append(p)
		var phrase := " ".join(words)
		if seen.has(phrase):
			continue
		seen[phrase] = true
		out.append({"phrase": phrase, "id": e[1], "slots": slots})
	return out


## A phrase with sample values in its slots ("enemy within 5").
static func example(pattern: Array, samples: Dictionary = {}) -> String:
	var words := []
	for p in pattern:
		if SAMPLE.has(p):
			words.append(String(samples.get(p, SAMPLE[p])))
		else:
			words.append(p)
	return " ".join(words)


## The best guesses for words the parser didn't know: up to three phrases, closest first.
static func closest(toks: Array, table: Array, n := 3) -> Array[String]:
	var typed := " ".join(toks)
	var scored := []
	for ph in phrases(table):
		var phrase: String = ph["phrase"]
		var score := _similarity(typed, phrase, toks)
		scored.append([score, phrase])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array[String] = []
	for sc in scored:
		if sc[0] < 0.34 or out.size() >= n:
			break
		out.append(sc[1])
	return out


static func did_you_mean(toks: Array, table: Array) -> String:
	var c := closest(toks, table)
	if c.is_empty():
		return ""
	return " - did you mean " + " or ".join(c.map(func(x): return "'" + x + "'")) + "?"


## Phrases that continue what has been typed so far (for an editor's completion list).
static func complete(prefix: String, table: Array, n := 8) -> Array[String]:
	var p := prefix.strip_edges().to_lower()
	var out: Array[String] = []
	for ph in phrases(table):
		var phrase: String = ph["phrase"]
		if p == "" or phrase.begins_with(p) or phrase.find(" " + p) >= 0:
			out.append(phrase)
			if out.size() >= n:
				break
	return out


## Word overlap blended with edit distance on the whole phrase, 0..1.
static func _similarity(typed: String, phrase: String, toks: Array) -> float:
	var pw := phrase.split(" ", false)
	var hit := 0
	for t in toks:
		for w in pw:
			if String(t) == w or (String(t).length() > 3 and _lev(String(t), w) <= 1):
				hit += 1
				break
	var overlap := float(hit) / float(maxi(pw.size(), toks.size()))
	var lv := 1.0 - float(_lev(typed, phrase)) / float(maxi(typed.length(), phrase.length()))
	return overlap * 0.6 + lv * 0.4


static func _lev(a: String, b: String) -> int:
	if a == b:
		return 0
	var prev := []
	for j in b.length() + 1:
		prev.append(j)
	for i in a.length():
		var cur := [i + 1]
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			cur.append(mini(mini(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost))
		prev = cur
	return prev[b.length()]
