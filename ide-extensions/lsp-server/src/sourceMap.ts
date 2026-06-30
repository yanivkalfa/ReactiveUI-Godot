// Bidirectional, offset-based source map between a .guitkx document and the synthetic .gd
// "virtual document" we hand to @gdscript-analyzer/core. Each span is length-preserving: the embedded GDScript
// text (a {expr}, a setup region, an @if condition) is spliced into the virtual doc VERBATIM, so an
// offset inside a mapped span translates by a constant delta. This is the reusable, engine-free core
// (the analog of the Unity SourceMap.cs the research said reuses verbatim). Volar's *technique*,
// hand-rolled — no framework.

export interface Span {
  /** inclusive start offset in the .guitkx source */
  sourceStart: number;
  /** length of the mapped region (identical in source and generated) */
  length: number;
  /** inclusive start offset in the generated .gd */
  genStart: number;
}

export class SourceMap {
  private spans: Span[] = [];

  /** Record that `source[sourceStart..+length]` was copied verbatim to `gen[genStart..+length]`. */
  addSpan(sourceStart: number, genStart: number, length: number): void {
    if (length <= 0) return;
    this.spans.push({ sourceStart, genStart, length });
  }

  /** Map a .guitkx offset to the generated .gd offset, or null if not inside any embedded span. */
  toGenerated(sourceOffset: number): number | null {
    for (const s of this.spans) {
      if (sourceOffset >= s.sourceStart && sourceOffset <= s.sourceStart + s.length) {
        return s.genStart + (sourceOffset - s.sourceStart);
      }
    }
    return null;
  }

  /** Map a generated .gd offset back to the .guitkx offset, or null if it lands in glue code. */
  toSource(genOffset: number): number | null {
    for (const s of this.spans) {
      if (genOffset >= s.genStart && genOffset <= s.genStart + s.length) {
        return s.sourceStart + (genOffset - s.genStart);
      }
    }
    return null;
  }

  get spanCount(): number {
    return this.spans.length;
  }
}

// --- offset <-> LSP Position helpers (LSP speaks {line, character}; our map speaks offsets) ---

export interface Position {
  line: number;
  character: number;
}

/** Convert a character offset into a {line, character} position within `text`. */
export function offsetToPosition(text: string, offset: number): Position {
  let line = 0;
  let last = 0;
  for (let i = 0; i < offset && i < text.length; i++) {
    if (text[i] === "\n") {
      line++;
      last = i + 1;
    }
  }
  return { line, character: Math.min(offset, text.length) - last };
}

/** Convert a {line, character} position into a character offset within `text`. */
export function positionToOffset(text: string, pos: Position): number {
  let line = 0;
  let i = 0;
  for (; i < text.length && line < pos.line; i++) {
    if (text[i] === "\n") line++;
  }
  return i + pos.character;
}
