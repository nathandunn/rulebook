class_name RuleLibrary
extends RefCounted
## A library of rule files: the shipped ones (res://<dir>/*.<ext>) with the viewer's edits laid
## over them (one JSON file in user://, which is IndexedDB in a browser). An edit that doesn't
## parse is kept as text, but the shipped version stays in play until it does.
##
##   RuleLibrary.register("ai", "res://ai", ".ai", Brain.parse)
##   RuleLibrary.register("coach", "res://coaches", ".coach", Coach.parse, my_cross_check)
##   RuleLibrary.ensure()
##   var b: Brain = RuleLibrary.get_obj("ai", "Gunslinger")
##
## A parser takes the text and returns an object with `name: String` and `errors: Array`.
## A cross-check takes (obj) and returns more problems (names it refers to that don't exist).

static var EDITS := "user://rulebook_edits.json"
static var _kinds := {}        # kind -> {dir, ext, parse: Callable, check: Callable}
static var _shipped := {}      # kind -> name -> source
static var _order := {}        # kind -> [names]
static var _edits := {}        # kind -> name -> source
static var _parsed := {}       # kind -> name -> object
static var _loaded := false


static func register(kind: String, dir: String, ext: String, parse: Callable, check: Callable = Callable()) -> void:
	_kinds[kind] = {"dir": dir, "ext": ext, "parse": parse, "check": check}
	_shipped[kind] = {}
	_order[kind] = []
	_edits[kind] = {}
	_parsed[kind] = {}
	_loaded = false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for k in _kinds:
		_shipped[k] = {}
		_order[k] = []
		var dir := DirAccess.open(_kinds[k]["dir"])
		if dir == null:
			push_error("no %s" % _kinds[k]["dir"])
			continue
		var files: Array[String] = []
		for f in dir.get_files():
			if f.ends_with(_kinds[k]["ext"]):
				files.append(f)
		files.sort()
		for f in files:
			var text := FileAccess.get_file_as_string(_kinds[k]["dir"] + "/" + f)
			var nm := name_of(k, text)
			if nm == "":
				push_warning("%s has no name" % f)
				continue
			_shipped[k][nm] = text
			_order[k].append(nm)
	_load_edits()
	for k in _kinds:
		_parsed[k] = {}
		for n in _order[k]:
			_reparse(k, n)


static func parse(kind: String, text: String) -> Variant:
	return (_kinds[kind]["parse"] as Callable).call(text)


static func name_of(kind: String, text: String) -> String:
	return String(parse(kind, text).name)


static func _load_edits() -> void:
	if not FileAccess.file_exists(EDITS):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(EDITS))
	if not (j is Dictionary):
		return
	for k in _kinds:
		if (j as Dictionary).has(k) and j[k] is Dictionary:
			for n in j[k]:
				_edits[k][n] = String(j[k][n])
				if not _order[k].has(n):
					_order[k].append(n)


static func _save_edits() -> void:
	var f := FileAccess.open(EDITS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_edits))


static func _reparse(kind: String, n: String) -> void:
	var obj: Variant = null
	if _edits[kind].has(n):
		obj = parse(kind, _edits[kind][n])
		if not (obj.errors as Array).is_empty():
			obj = null
	if obj == null and _shipped[kind].has(n):
		obj = parse(kind, _shipped[kind][n])
	if obj != null:
		_parsed[kind][n] = obj
	else:
		_parsed[kind].erase(n)


static func names(kind: String) -> Array:
	ensure()
	return (_order[kind] as Array).filter(func(n): return _parsed[kind].has(n))


static func get_obj(kind: String, n: String) -> Variant:
	ensure()
	return _parsed[kind].get(n, null)


## What the editor shows: the edit if there is one, else the shipped file.
static func source(kind: String, n: String) -> String:
	ensure()
	return _edits[kind].get(n, _shipped[kind].get(n, ""))


static func is_edited(kind: String, n: String) -> bool:
	ensure()
	return _edits[kind].has(n)


static func is_shipped(kind: String, n: String) -> bool:
	ensure()
	return _shipped[kind].has(n)


## Every problem with a text: its own parse errors and the kind's cross-check.
static func lint(kind: String, text: String) -> Array[String]:
	ensure()
	var obj: Variant = parse(kind, text)
	var errs: Array[String] = []
	errs.append_array(obj.errors)
	var chk: Callable = _kinds[kind]["check"]
	if chk.is_valid() and errs.is_empty():
		errs.append_array(chk.call(obj))
	return errs


## Save edited text; a new name is saved as a new entry. Returns [problems, name]; nothing is
## saved when there are problems.
static func save(kind: String, text: String) -> Array:
	var errs := lint(kind, text)
	if not errs.is_empty():
		return [errs, ""]
	var n := name_of(kind, text)
	if _shipped[kind].get(n, "") == text:
		_edits[kind].erase(n)
	else:
		_edits[kind][n] = text
	if not _order[kind].has(n):
		_order[kind].append(n)
	_reparse(kind, n)
	_save_edits()
	return [errs, n]


## Back to the shipped file (or gone, for a name the viewer made).
static func reset(kind: String, n: String) -> void:
	ensure()
	_edits[kind].erase(n)
	if not _shipped[kind].has(n):
		_order[kind].erase(n)
	_reparse(kind, n)
	_save_edits()


static func reset_all() -> void:
	ensure()
	for k in _kinds:
		for n in (_edits[k] as Dictionary).keys():
			reset(k, n)


## Everything edited, as one JSON text (to copy and share), and back.
static func export_edits() -> String:
	ensure()
	return JSON.stringify(_edits, "  ")


static func import_edits(text: String) -> Array[String]:
	var j: Variant = JSON.parse_string(text)
	var errs: Array[String] = []
	if not (j is Dictionary):
		errs.append("that isn't an export (JSON)")
		return errs
	for k in _kinds:
		if (j as Dictionary).has(k):
			for n in j[k]:
				var r := save(k, String(j[k][n]))
				for e in r[0]:
					errs.append("%s \"%s\": %s" % [k, n, e])
	return errs
