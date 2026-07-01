@tool
class_name GuitkxTokenizer
extends RefCounted
## A small, line-oriented tokenizer for .guitkx, written for syntax highlighting.
##
## Why this exists: RUIGuitkxLexer is NOT a token producer — it only exposes static scan primitives
## (skip_noncode / find_matching / keyword_at). This class reuses those primitives to classify a
## single line into coloured spans. It is intentionally per-line and self-contained: Godot calls the
## highlighter's _get_line_syntax_highlighting(line) one line at a time with no guaranteed order, so
## carrying state across lines is unreliable. Constructs that span lines (a `{expr}` or a triple-quoted
## string opened on an earlier line) are highlighted best-effort on each line in isolation.
##
## tokenize_line() returns an ordered, non-overlapping Array of { "start": int, "end": int (exclusive),
## "kind": String }. Only classified runs are emitted; anything else is left to the editor's default
## text colour. Pure and FileAccess-free, so it is headlessly unit-testable.

enum { K_COMMENT, K_STRING, K_TAG, K_ATTR, K_EXPR, K_DIRECTIVE, K_KEYWORD, K_NUMBER, K_SYMBOL }

# Kept as strings in the output so callers/tests read clearly; enum above documents the closed set.
const KIND := {
	K_COMMENT: "comment", K_STRING: "string", K_TAG: "tag", K_ATTR: "attr",
	K_EXPR: "expr", K_DIRECTIVE: "directive", K_KEYWORD: "keyword",
	K_NUMBER: "number", K_SYMBOL: "symbol",
}

# GDScript + .guitkx declaration/control keywords (appear in setup blocks and @directives).
const KEYWORDS := {
	"component": true, "hook": true, "module": true,
	"func": true, "var": true, "const": true, "enum": true, "signal": true, "class": true,
	"class_name": true, "extends": true, "static": true, "return": true, "pass": true,
	"break": true, "continue": true, "await": true, "yield": true, "super": true, "self": true,
	"if": true, "elif": true, "else": true, "for": true, "while": true, "match": true,
	"in": true, "as": true, "is": true, "and": true, "or": true, "not": true,
	"true": true, "false": true, "null": true, "void": true, "use": true,
}

const _SYMBOLS := "<>/={}()[],.:;+-*%&|!?"

func tokenize_line(text: String) -> Array:
	var out: Array = []
	var n := text.length()
	var i := 0
	while i < n:
		var c := text[i]
		# 1. Strings and # comments, via the proven lexer primitive (handles r"" &"" ^"" $"" %"" prefixes,
		#    triple quotes, and backslash escapes). skip_noncode returns the index just past the run.
		if c == "#" or c == "\"" or c == "'":
			var j: int = RUIGuitkxLexer.skip_noncode(text, i)
			if j > i:
				out.append({"start": i, "end": j, "kind": ("comment" if c == "#" else "string")})
				i = j
				continue
		# 2. Embedded-GDScript expression { ... } — colour the whole balanced region.
		if c == "{":
			var close: int = RUIGuitkxLexer.find_matching(text, i)
			var end := (close + 1) if close >= 0 else n
			out.append({"start": i, "end": end, "kind": "expr"})
			i = end
			continue
		# 3. Tag: `<Name`, `</Name` — colour the `<` / `</` as symbol and the name as a tag.
		if c == "<":
			var k := i + 1
			if k < n and text[k] == "/":
				k += 1
			if k < n and _is_name_start(text[k]):
				out.append({"start": i, "end": k, "kind": "symbol"})
				var m := k
				while m < n and _is_name(text[m]):
					m += 1
				out.append({"start": k, "end": m, "kind": "tag"})
				i = m
				continue
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			i += 1
			continue
		# 4. @directive (@if, @for, @match, @class_name, ...).
		if c == "@":
			var m := i + 1
			while m < n and _is_name(text[m]):
				m += 1
			if m > i + 1:
				out.append({"start": i, "end": m, "kind": "directive"})
				i = m
				continue
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			i += 1
			continue
		# 5. Numbers.
		if _is_digit(c):
			var m := i
			while m < n and (_is_digit(text[m]) or text[m] == "." or text[m] == "_" \
					or "abcdefABCDEFxXbo".contains(text[m])):
				m += 1
			out.append({"start": i, "end": m, "kind": "number"})
			i = m
			continue
		# 6. Identifiers: a keyword, or a .guitkx attribute name (`name=` immediately before a value).
		if _is_name_start(c):
			var m := i
			while m < n and _is_name(text[m]):
				m += 1
			var word := text.substr(i, m - i)
			if KEYWORDS.has(word):
				out.append({"start": i, "end": m, "kind": "keyword"})
			elif _is_attr_name(text, m, n):
				out.append({"start": i, "end": m, "kind": "attr"})
			# else: plain identifier — leave to default colour.
			i = m
			continue
		# 7. Punctuation / operators.
		if _SYMBOLS.contains(c):
			out.append({"start": i, "end": i + 1, "kind": "symbol"})
			i += 1
			continue
		i += 1
	return out

# An identifier is an attribute name only if the next non-space char is `=` AND the value after it is a
# .guitkx attribute value (a string or a `{expr}`). This avoids painting GDScript assignments (`x = 5`)
# inside setup blocks as attributes.
func _is_attr_name(text: String, after: int, n: int) -> bool:
	var j := after
	while j < n and (text[j] == " " or text[j] == "\t"):
		j += 1
	if j >= n or text[j] != "=":
		return false
	j += 1
	while j < n and (text[j] == " " or text[j] == "\t"):
		j += 1
	if j >= n:
		return false
	var v := text[j]
	return v == "\"" or v == "'" or v == "{"

func _is_name_start(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

func _is_name(c: String) -> bool:
	return _is_name_start(c) or _is_digit(c)

func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"
