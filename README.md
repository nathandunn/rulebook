# Rulebook — a tiny readable rule language for game AI

A Godot 4 addon. Game AI written as plain rules that a player can read and edit:

```
when enemy within 5 yards and not health under 30% -> attack; shout
when (health under 0.3 or enemy within 2m) for 1.5s -> flee 10
otherwise -> patrol
```

Rules are read top to bottom; the first whose condition holds — and whose action can be done —
decides. There is no `eval`: only the words your game registers. Used by
[Gridiron Bots](https://github.com/nathandunn/gridiron-bots) (coaches, plays and position brains)
and the language started life in [Drillbook Bots](https://github.com/nathandunn/drillbook-bots).

## Install
Copy `addons/rulebook/` into your project. Three classes, no autoloads:

| Class | What it does |
|---|---|
| `Dsl` | Parse rules against pattern tables, run them with your `sense` and `act` callables |
| `RuleHelp` | Phrases for a word list, examples, *did you mean …*, completions |
| `RuleLibrary` | Rule files shipped in `res://` with the player's edits laid over them (`user://`), lint, save, reset, export/import |

## Vocabulary: pattern tables
A table is a list of `[tokens, id]`. Slots: `#D` distance (yards; `m`/`metres` converted),
`#P` percent (`30%` or `0.3`), `#S` seconds (`2s`), `#X` number, `$W` one word (quotes allowed),
`$R` the rest of the atom. The first pattern that consumes every token wins, so put the free-word
patterns (`$W`) last.

```gdscript
const CONDITIONS := [
	[["enemy", "within", "#D"], "enemy_within"],
	[["health", "under", "#P"], "health_under"],
	[["mode", "is", "$W"], "mode_is"],
]
const ACTIONS := [
	[["attack"], "attack"],
	[["flee", "#D"], "flee"],
	[["call", "$R"], "call"],          # call "Plan B" or "Plan C"  ->  Dsl.names_in(args[0])
]
```

## Parsing and running
```gdscript
var errors := []
var rule := Dsl.parse_rule(Dsl.lower_outside_quotes(line), line_no, CONDITIONS, ACTIONS, errors, "guard")
# errors: "line 3: don't know the condition 'enemy withn 5' - did you mean 'enemy within N'?"

var decided_line := Dsl.run(rules, sense, act, memory, now, MODIFIERS, tally)
#   sense(id, args) -> bool    is the condition true now?
#   act(id, args)   -> bool    do it if you can (false = try the next rule)
#   MODIFIERS       ids that set a manner and let the next rule be read (e.g. "wrap up")
#   memory          per-actor Dictionary, keeps the 'for Ns' timers
#   tally           line -> times that rule decided (for "which rules did the work" reports)
```
Conditions: `and`, `or`, `not`, parentheses, and `<condition> for Ns` or `(<group>) for Ns`
(true only once it has held that long). A rule is `when <condition> -> <action>; <action>` or
`otherwise -> ...`. `#` starts a comment.

## Help for people writing rules
```gdscript
RuleHelp.phrases(CONDITIONS)        # [{phrase: "enemy within N", id, slots}, ...] for a word list
RuleHelp.example(CONDITIONS[0][0])  # "enemy within 5"
RuleHelp.complete("enemy", CONDITIONS)   # ["enemy within N"] for a CodeEdit completion popup
RuleHelp.did_you_mean(["atack"], ACTIONS) # " - did you mean 'attack'?"
```

## A library of rule files
```gdscript
RuleLibrary.EDITS = "user://mygame_edits.json"
RuleLibrary.register("ai", "res://ai", ".ai", Brain.parse)            # parse(text) -> obj with .name, .errors
RuleLibrary.register("coach", "res://coaches", ".coach", Coach.parse, check_refs)  # optional cross-check
var b: Brain = RuleLibrary.get_obj("ai", "Gunslinger")
RuleLibrary.lint("ai", text)     # problems, with line numbers
RuleLibrary.save("ai", text)     # [problems, name] - saved over the shipped file, or as new if renamed
RuleLibrary.reset("ai", "Gunslinger")
RuleLibrary.export_edits() / import_edits(json)
```
An edit that doesn't parse is kept as text, but the shipped version stays in use until it does.

## Tests
`godot --headless --path . -s tests/run_tests.gd`
