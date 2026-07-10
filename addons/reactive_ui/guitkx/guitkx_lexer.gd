class_name RUIGuitkxLexer
extends RefCounted
## The load-bearing scanner for the .guitkx compiler — the GDScript-lexis port of uitkx's
## string/char/comment-skipping state machine (which appears 3x in the C# code). Everything
## that finds balanced regions (the `return (...)` markup window, `{expr}` attributes,
## `<Tag>...</Tag>` children) MUST route through `skip_noncode` first so braces/quotes/comments
## inside embedded GDScript never confuse delimiter balancing.
##
## GDScript lexis (vs C#): comments are `#` to end-of-line only (NO `/* */`); strings are
## "..." / '...' / triple-quoted """...""" / '''...''' with `\` escapes; optional one-char
## prefixes r"" (raw), &"" (StringName), ^"" (NodePath). No C# `$"`/`@"`/interpolation.

## If `i` sits at the start of a comment or string literal, skip the whole token and return the
## index just past it. Otherwise return `i` unchanged. Never advances past `len`.
static func skip_noncode(src: String, i: int) -> int:
	var n := src.length()
	if i >= n:
		return i
	var c := src[i]
	# line comment
	if c == "#":
		var j := i + 1
		while j < n and src[j] != "\n":
			j += 1
		return j
	# string, with optional one-char prefix: r"" (raw), &"" (StringName), ^"" (NodePath),
	# $"" / %"" (node-path string forms). The prefix only counts at a TOKEN START — not when the
	# char is itself an operator following a value (e.g. "fmt" % args, a & b, arr[i]^2) — so we
	# never mis-skip code as a string. Must stay byte-identical with scanner.ts skipNoncode.
	var q_at := i
	if c == "r" or c == "&" or c == "^" or c == "$" or c == "%":
		if i + 1 < n and (src[i + 1] == "\"" or src[i + 1] == "'") and (i == 0 or not _is_value_end(src[i - 1])):
			q_at = i + 1
	if q_at < n and (src[q_at] == "\"" or src[q_at] == "'"):
		return _skip_string(src, q_at)
	return i

# True if `c` can end a value/operand, so a following r/&/^/$/% is an operator, not a string prefix.
static func _is_value_end(c: String) -> bool:
	return _is_ident(c) or c == ")" or c == "]" or c == "\"" or c == "'"

## `i` points at a quote char. Skip the string (handles triple-quoted + escapes). Returns the
## index just past the closing quote (or `len` if unterminated).
static func _skip_string(src: String, i: int) -> int:
	var n := src.length()
	var q := src[i]
	# triple-quoted (spans newlines)
	if i + 2 < n and src[i + 1] == q and src[i + 2] == q:
		var j := i + 3
		while j < n:
			if src[j] == "\\":
				j += 2
				continue
			if src[j] == q and j + 2 < n and src[j + 1] == q and src[j + 2] == q:
				return j + 3
			j += 1
		return n
	# single/double-quoted
	var k := i + 1
	while k < n:
		var ch := src[k]
		if ch == "\\":
			k += 2
			continue
		if ch == q:
			return k + 1
		if ch == "\n":   # GDScript single-line strings don't span newlines
			return k
		k += 1
	return n

## Find the index of the matching close delimiter for the `open` char at `open_i`, skipping
## noncode. `open_i` must point at the opening delimiter. Returns the index OF the close char,
## or -1 if unbalanced. Handles nested ()/{}/[] of any kind.
static func find_matching(src: String, open_i: int) -> int:
	var n := src.length()
	var stack: Array = []
	var i := open_i
	while i < n:
		var j := skip_noncode(src, i)
		if j != i:
			i = j
			continue
		var c := src[i]
		if c == "(" or c == "{" or c == "[":
			stack.append(c)
		elif c == ")" or c == "}" or c == "]":
			if stack.is_empty():
				return -1
			var top: String = stack.pop_back()
			if (c == ")" and top != "(") or (c == "}" and top != "{") or (c == "]" and top != "["):
				return -1
			if stack.is_empty():
				return i
		i += 1
	return -1

## [G-01 fix] Markup-lexis noncode skip: comments are `//` (to EOL), `/* ... */`, and
## `<!-- ... -->`; `#` is NOT a comment (it is a literal character in markup text, e.g. a color
## literal or a stray "Score #3"). Strings are still "..."/'...' (incl. triple-quoted, escapes) via
## _skip_string -- no r""/&""/^""/$""/%"" prefix detection, since that is a GDScript-code
## convention, not a markup one. Used by find_matching_markup for spans whose content is primarily
## MARKUP (component/directive bodies, the `return ( ... )` window) rather than a GDScript
## statement. Must stay byte-identical with scanner.ts skipNoncodeMarkup.
static func skip_noncode_markup(src: String, i: int) -> int:
	var n := src.length()
	if i >= n:
		return i
	var c := src[i]
	if c == "/" and i + 1 < n and src[i + 1] == "/":
		var j := i + 2
		while j < n and src[j] != "\n":
			j += 1
		return j
	if c == "/" and i + 1 < n and src[i + 1] == "*":
		var close := src.find("*/", i + 2)
		return (close + 2) if close != -1 else n
	if c == "<" and i + 3 < n and src[i + 1] == "!" and src[i + 2] == "-" and src[i + 3] == "-":
		var close := src.find("-->", i + 4)
		return (close + 3) if close != -1 else n
	if c == "\"" or c == "'":
		return _skip_string(src, i)
	return i

## [G-01 fix] Mode-aware counterpart to find_matching for spans whose content mixes MARKUP with
## embedded GDScript ({expr} attribute/child holes, directive/@case headers, setup/prelude
## statements, `return (...)` windows) -- e.g. a directive body, a component body, or the
## `return ( ... )` window itself. The naive GDScript-lexis find_matching treats a literal `#` in
## markup text (or a markup `//`/`/* */`/`<!-- -->` comment) as GDScript lexis, silently
## miscounting the delimiters it is meant to balance (G-01).
##
## [G-23 fix] Content mode is tracked PER DELIMITER-STACK LEVEL, not globally:
##   - `{` opens a BODY level (component/directive body: GDScript prelude statements mixed with
##     markup) -- including `open_i` itself when it is a `{`. Within a BODY level the lexis is
##     LINE-CLASSIFIED (_is_markup_line): a line whose first non-ws char is `<`, `{`, `//`, `/*`,
##     or a directive `@keyword` scans as markup (`#` literal); any other line is GDScript prelude
##     and scans as code (`#` = comment). This is what fixes G-23 -- a `(`/`{` inside a prelude
##     `#`/`##` comment no longer desyncs the stack (previously the prelude was scanned as markup,
##     so the comment's `(` opened a code island whose closing `)` on the NEXT comment line was
##     then comment-skipped -- unclosed forever).
##   - `(` after a bare `return` keyword opens a MARKUP level (the return window) -- including
##     `open_i` itself when it is a `(`. MARKUP levels always scan with markup lexis regardless of
##     line shape (`return ( <Label>Score #3</Label> )` on a prelude-classified line keeps `#3`
##     literal). Any other `(` is a directive/@case header and opens a CODE level; `{` not
##     following a header-close/`@else`/`@default` is an `{expr}` island -- CODE as well. A `[`
##     inherits the current level's mode (markup text brackets stay markup; prelude array
##     literals scan as code, so their `#` comments are comments).
##   - CODE levels use ordinary GDScript lexis via skip_noncode all the way down -- real GDScript
##     has no markup/code ambiguity internally. A header/case-value close re-arms "the next `{`
##     is a body".
## (A bare `(` in literal markup text, matching neither keyword, is a pre-existing, out-of-scope
## edge case -- it defaults to a header, the more common construct.)
## Must stay byte-identical with scanner.ts findMatchingMarkup.
const _MODE_BODY := 0
const _MODE_MARKUP := 1
const _MODE_CODE := 2

static func find_matching_markup(src: String, open_i: int) -> int:
	var n := src.length()
	var delims: Array = [src[open_i]]
	var modes: Array = [_MODE_BODY if src[open_i] == "{" else _MODE_MARKUP]
	var expect_body := false
	var expect_markup_paren := false
	# [G-23] Per-line classification state for BODY levels (see docstring).
	var line_start: int = src.rfind("\n", open_i) + 1
	var line_end := src.find("\n", open_i)
	if line_end == -1:
		line_end = n
	var line_markup := _is_markup_line(src, line_start, line_end)
	var i := open_i + 1
	while i < n:
		while i > line_end:
			line_start = line_end + 1
			line_end = src.find("\n", line_start)
			if line_end == -1:
				line_end = n
			line_markup = _is_markup_line(src, line_start, line_end)
		var mode: int = modes[modes.size() - 1]
		var in_code := mode == _MODE_CODE
		var markup_lexis := mode == _MODE_MARKUP or (mode == _MODE_BODY and line_markup)
		var j: int = skip_noncode_markup(src, i) if markup_lexis else skip_noncode(src, i)
		if j != i:
			i = j
			continue
		var c := src[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue
		if not in_code:
			if c == "@" and keyword_at(src, i + 1, "else"):
				expect_body = true
				expect_markup_paren = false
				i += 5   # "@else"
				continue
			if c == "@" and keyword_at(src, i + 1, "default"):
				expect_body = true
				expect_markup_paren = false
				i += 8   # "@default"
				continue
			if c == "r" and keyword_at(src, i, "return"):
				expect_markup_paren = true
				expect_body = false
				i += 6   # "return"
				continue
			if c == "(":
				delims.append(c)
				modes.append(_MODE_MARKUP if expect_markup_paren else _MODE_CODE)
				expect_body = false
				expect_markup_paren = false
				i += 1
				continue
			if c == "{":
				delims.append(c)
				modes.append(_MODE_BODY if expect_body else _MODE_CODE)
				expect_body = false
				expect_markup_paren = false
				i += 1
				continue
			if c == "[":
				delims.append(c)
				modes.append(mode)   # inherit -- markup text brackets stay markup, prelude arrays stay code
				expect_body = false
				expect_markup_paren = false
				i += 1
				continue
			if c == ")" or c == "}" or c == "]":
				if delims.is_empty():
					return -1
				var top: String = delims.pop_back()
				modes.pop_back()
				if (c == ")" and top != "(") or (c == "}" and top != "{") or (c == "]" and top != "["):
					return -1
				if delims.is_empty():
					return i
				i += 1
				continue
			expect_body = false
			expect_markup_paren = false
			i += 1
			continue
		else:
			if c == "(" or c == "{" or c == "[":
				delims.append(c)
				modes.append(_MODE_CODE)
				i += 1
				continue
			if c == ")" or c == "}" or c == "]":
				if delims.is_empty():
					return -1
				var top: String = delims.pop_back()
				modes.pop_back()
				if (c == ")" and top != "(") or (c == "}" and top != "{") or (c == "]" and top != "["):
					return -1
				if delims.is_empty():
					return i
				if modes[modes.size() - 1] != _MODE_CODE:
					expect_body = (top == "(")
				i += 1
				continue
			i += 1
			continue
	return -1

## [G-23] Line classification for BODY levels: does this line's content read as markup (elements,
## expr children, markup comments, directives) rather than a GDScript prelude statement? Decided
## by the first non-ws char -- the same convention the compiler's body splitter applies to parts.
static func _is_markup_line(src: String, ls: int, le: int) -> bool:
	var k := ls
	while k < le:
		var c := src[k]
		if c == " " or c == "\t" or c == "\r":
			k += 1
			continue
		if c == "<" or c == "{":
			return true
		if c == "/" and k + 1 < le and (src[k + 1] == "/" or src[k + 1] == "*"):
			return true
		if c == "@":
			return keyword_at(src, k + 1, "if") or keyword_at(src, k + 1, "elif") \
					or keyword_at(src, k + 1, "else") or keyword_at(src, k + 1, "for") \
					or keyword_at(src, k + 1, "while") or keyword_at(src, k + 1, "match") \
					or keyword_at(src, k + 1, "case") or keyword_at(src, k + 1, "default")
		return false
	return false

## True if `src.substr(i)` begins with `word` AND `word` is bounded by non-identifier chars on
## both sides (a real keyword, not a substring of a longer identifier). [port of TryReadKeywordAt]
static func keyword_at(src: String, i: int, word: String) -> bool:
	var n := src.length()
	var wl := word.length()
	if i + wl > n:
		return false
	if src.substr(i, wl) != word:
		return false
	if i > 0 and _is_ident(src[i - 1]):
		return false
	if i + wl < n and _is_ident(src[i + wl]):
		return false
	return true

static func _is_ident(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
