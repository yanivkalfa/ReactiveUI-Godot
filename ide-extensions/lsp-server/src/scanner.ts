// TypeScript port of the .guitkx GDScript-lexis scanner (addons/reactive_ui/guitkx/guitkx_lexer.gd).
// Everything that finds balanced regions or extracts embedded-GDScript spans routes through
// skipNoncode first so braces/quotes/comments inside the embedded code never confuse balancing.
// GDScript lexis: `#` line comments; "..."/'...'/triple-quoted strings; r"/&"/^" prefixes; no C#.

export function isIdent(c: string): boolean {
  return c === "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9");
}

/** If `i` sits at a comment or string literal, return the index just past it; else return `i`. */
export function skipNoncode(src: string, i: number): number {
  const n = src.length;
  if (i >= n) return i;
  const c = src[i];
  if (c === "#") {
    let j = i + 1;
    while (j < n && src[j] !== "\n") j++;
    return j;
  }
  let qAt = i;
  if (c === "r" || c === "R" || c === "&" || c === "^") {
    if (i + 1 < n && (src[i + 1] === '"' || src[i + 1] === "'")) qAt = i + 1;
  }
  if (qAt < n && (src[qAt] === '"' || src[qAt] === "'")) return skipString(src, qAt);
  return i;
}

/** `i` points at a quote. Skip the string (triple-quoted + escapes). Returns index past close. */
export function skipString(src: string, i: number): number {
  const n = src.length;
  const q = src[i];
  if (i + 2 < n && src[i + 1] === q && src[i + 2] === q) {
    let j = i + 3;
    while (j < n) {
      if (src[j] === "\\") {
        j += 2;
        continue;
      }
      if (src[j] === q && j + 2 < n && src[j + 1] === q && src[j + 2] === q) return j + 3;
      j++;
    }
    return n;
  }
  let k = i + 1;
  while (k < n) {
    const ch = src[k];
    if (ch === "\\") {
      k += 2;
      continue;
    }
    if (ch === q) return k + 1;
    if (ch === "\n") return k;
    k++;
  }
  return n;
}

/** Index of the matching close delimiter for the opener at `openI`, skipping noncode; -1 if none. */
export function findMatching(src: string, openI: number): number {
  const n = src.length;
  const stack: string[] = [];
  let i = openI;
  while (i < n) {
    const j = skipNoncode(src, i);
    if (j !== i) {
      i = j;
      continue;
    }
    const c = src[i];
    if (c === "(" || c === "{" || c === "[") {
      stack.push(c);
    } else if (c === ")" || c === "}" || c === "]") {
      if (stack.length === 0) return -1;
      const top = stack.pop()!;
      if ((c === ")" && top !== "(") || (c === "}" && top !== "{") || (c === "]" && top !== "[")) return -1;
      if (stack.length === 0) return i;
    }
    i++;
  }
  return -1;
}

/** True if `word` starts at `i` and is bounded by non-identifier chars (a real keyword). */
export function keywordAt(src: string, i: number, word: string): boolean {
  const n = src.length;
  const wl = word.length;
  if (i + wl > n) return false;
  if (src.substr(i, wl) !== word) return false;
  if (i > 0 && isIdent(src[i - 1])) return false;
  if (i + wl < n && isIdent(src[i + wl])) return false;
  return true;
}
