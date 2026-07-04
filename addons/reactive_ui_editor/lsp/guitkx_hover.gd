@tool
class_name GuitkxHover
extends RefCounted
## Pure hover-text provider for `.guitkx` markup: given a caret over a tag / attribute / directive,
## returns Markdown describing it (Godot class, property/signal type, directive form). Reuses the
## GuitkxSchema hover builders + GuitkxWorkspace index; UI-free so it is unit-testable headlessly.
## Embedded-GDScript hover is left to the analyzer layer (Phase 4). [Phase 1]

## Markdown hover for the identifier under char `offset` in `text`, or "" if nothing to say.
static func for_caret(text: String, offset: int) -> String:
	var word := word_at(text, offset)
	if word == "":
		return ""
	var start := _word_start(text, offset)
	var ctx := GuitkxContext.classify(text, start)
	match ctx["kind"]:
		GuitkxContext.KIND_TAG, GuitkxContext.KIND_MARKUP:
			return _tag_hover(word)
		GuitkxContext.KIND_ATTR:
			var h := GuitkxSchema.hover_for_attribute(str(ctx["tag"]), word)
			return h
		GuitkxContext.KIND_DIRECTIVE:
			return GuitkxSchema.hover_for_directive("@" + word)
	# Fallback: the word is a bare tag/component identifier somewhere the classifier read as markup.
	return _tag_hover(word)

static func _tag_hover(word: String) -> String:
	if GuitkxSchema.is_host_tag(word):
		return GuitkxSchema.hover_for_tag(word)
	if GuitkxWorkspace.is_component(word):
		var e := GuitkxWorkspace.lookup(word)
		return "**`<%s>`** — user component (`%s`). Ctrl-click to open its declaration." % [word, (e.get("path", "") as String).get_file()]
	return ""

## The full identifier spanning `offset` (expands both directions over identifier chars).
static func word_at(text: String, offset: int) -> String:
	var s := _word_start(text, offset)
	var e := offset
	while e < text.length() and _is_ident(text.unicode_at(e)):
		e += 1
	return text.substr(s, e - s)

static func _word_start(text: String, offset: int) -> int:
	var i := clampi(offset, 0, text.length())
	while i > 0 and _is_ident(text.unicode_at(i - 1)):
		i -= 1
	return i

static func _is_ident(c: int) -> bool:
	return c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
