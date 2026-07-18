// Classify what the cursor is sitting in, to route completion/hover: markup contexts (tag name,
// attribute name, a `<`/`@` start) are answered from the schema; everything else (setup, {expr},
// control-flow conditions) is treated as embedded GDScript and analyzed by @gdscript-analyzer/core.

import { skipString, findMatching } from "./scanner";
import { isBodyBrace } from "./semanticTokens";
import { markupWindows } from "./formatGuitkx";

export type ContextKind = "tagName" | "attrName" | "directive" | "embedded" | "markup";

export interface CursorContext {
  kind: ContextKind;
  /** the enclosing tag name, when kind === "attrName" */
  tag?: string;
  /** the word fragment immediately before the cursor (what the user is typing) */
  word: string;
}

export function classifyContext(src: string, offset: number): CursorContext {
  const word = wordBefore(src, offset);

  const tag = enclosingTag(src, offset);
  if (tag) {
    // enclosingTag already returns null when the cursor is inside any {expr} (incl. an ={...} attr
    // value), so reaching here means the cursor is in the tag's name or attribute-name area.
    const afterLt = src.slice(tag.ltPos + 1, offset);
    if (/^[A-Za-z0-9_]*$/.test(afterLt)) return { kind: "tagName", word };
    return { kind: "attrName", tag: tag.name, word };
  }

  // immediate `<` (new child tag) / `@` (directive) at a markup position
  const prevNonWs = lastNonWs(src, offset);
  if (prevNonWs === "<") return { kind: "tagName", word };
  if (src.slice(Math.max(0, offset - word.length - 1), offset).startsWith("@")) {
    return { kind: "directive", word: "@" + word };
  }

  // Not in a tag and not starting markup punctuation. Distinguish embedded GDScript from a blank markup
  // position. The cursor is EMBEDDED when it is:
  //  - outside every markup window (component setup, params, a hook/module body) — plain GDScript; or
  //  - inside an {expr} hole (the innermost open `{` is NOT a control-flow / component BODY brace); or
  //  - inside an @directive `(...)` condition (an unmatched paren earlier on the line); or
  //  - on a line that begins with a GDScript statement keyword (a setup statement).
  // Otherwise it is a markup position — a blank child slot or an @for/@if body. BUG-7: a blank slot
  // inside a control-flow / component BODY brace used to be misread as embedded (the brace was unmatched),
  // so tag/component completion never fired there.
  const openBrace = innermostOpenBrace(src, offset);
  const inExprHole = openBrace !== -1 && !isBodyBrace(src, openBrace);
  if (!inMarkupWindow(src, offset) || inExprHole || insideUnmatchedParen(src, offset) || looksLikeSetup(src, offset)) {
    return { kind: "embedded", word };
  }
  return { kind: "markup", word };
}

// --- helpers ---

function wordBefore(src: string, offset: number): string {
  let i = offset;
  while (i > 0 && /[A-Za-z0-9_]/.test(src[i - 1])) i--;
  return src.slice(i, offset);
}

function lastNonWs(src: string, offset: number): string {
  let i = offset - 1;
  while (i >= 0 && /\s/.test(src[i])) i--;
  return i >= 0 ? src[i] : "";
}

interface TagAt {
  ltPos: number;
  name: string;
}

/** Nearest `<Tag` opener before `offset` with no closing `>` between it and the cursor (and the
 *  `<` not inside a string). Returns null if we're not inside an open tag. */
function enclosingTag(src: string, offset: number): TagAt | null {
  // scan forward from a recent point, tracking the last opened-but-unclosed tag
  let i = Math.max(0, src.lastIndexOf("\n", offset) - 400); // bounded look-back for performance
  let openLt = -1;
  while (i < offset) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "{") {
      if (isBodyBrace(src, i)) {
        i++; // a component/control-flow BODY brace contains markup — enter it
        continue;
      }
      // a child/attr {expr} hole: a `<` inside is GDScript, not a tag. Cursor inside -> embedded.
      const close = findMatching(src, i);
      if (close === -1 || close >= offset) return null;
      i = close + 1;
      continue;
    }
    if (c === "<" && i + 1 < src.length && /[A-Za-z]/.test(src[i + 1])) {
      openLt = i;
    } else if (c === ">") {
      openLt = -1;
    }
    i++;
  }
  if (openLt === -1) return null;
  let j = openLt + 1;
  while (j < src.length && /[A-Za-z0-9_]/.test(src[j])) j++;
  return { ltPos: openLt, name: src.slice(openLt + 1, j) };
}

// The innermost `{` still open at `offset` (string/comment-aware), or -1. Lets the caller ask whether
// that brace is a markup BODY brace (component/control-flow) vs an {expr} hole.
function innermostOpenBrace(src: string, offset: number): number {
  const stack: number[] = [];
  let i = 0;
  while (i < offset) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i);
      continue;
    }
    if (c === "#") {
      while (i < offset && src[i] !== "\n") i++;
      continue;
    }
    if (c === "{") stack.push(i);
    else if (c === "}") stack.pop();
    i++;
  }
  return stack.length ? stack[stack.length - 1] : -1;
}

// True when `offset` is inside some component's markup window (its return(...) region).
function inMarkupWindow(src: string, offset: number): boolean {
  for (const w of markupWindows(src)) if (offset >= w.start && offset <= w.end) return true;
  return false;
}

function insideUnmatchedParen(src: string, offset: number): boolean {
  // an unmatched '(' on the current line (e.g. an @if/@for/@match condition) before the cursor
  const lineStart = src.lastIndexOf("\n", offset - 1) + 1;
  let depth = 0;
  for (let i = lineStart; i < offset; i++) {
    const c = src[i];
    if (c === '"' || c === "'") {
      i = skipString(src, i) - 1;
      continue;
    }
    if (c === "(") depth++;
    else if (c === ")") depth = Math.max(0, depth - 1);
  }
  return depth > 0;
}

/** Heuristic: the line begins with a statement keyword (var/const/if/for/...) — setup code. */
function looksLikeSetup(src: string, offset: number): boolean {
  const lineStart = src.lastIndexOf("\n", offset - 1) + 1;
  const line = src.slice(lineStart, offset).trimStart();
  return /^(var|const|if|elif|else|for|while|match|return|func|await|s\b)/.test(line);
}
