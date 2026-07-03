// Offset-unit boundary for everything interchanged with the GDScript toolchain (T0.2/T0.1).
//
// GDScript String indices count Unicode CODE POINTS; JavaScript string indices count UTF-16 CODE
// UNITS. They diverge by 1 for every astral-plane character (emoji, rare CJK) before the offset —
// exactly the class of bug the contract harness caught on its first run (demo files with 👋/🎯).
// The canonical unit for every GD↔TS interchange file (the .diags.json sidecar, the contract
// goldens) is therefore CODE POINTS — the compiler's native truth — and THIS module is the single
// place the TS side converts. (The gdscript-analyzer boundary is separate: analyzerAdapter.ts owns
// UTF-16 ↔ UTF-8 bytes there.)
//
// Fast path: a text with no surrogate pairs has identical units, so conversion is the identity.

const HAS_ASTRAL = /[\uD800-\uDBFF]/;

/** Convert a code-point offset (GDScript String index) to a UTF-16 offset into `text`. Negative
 *  offsets (the -1 "whole file" sentinel) pass through; offsets past the end clamp to text.length. */
export function cpToUtf16(text: string, cp: number): number {
  if (cp <= 0 || !HAS_ASTRAL.test(text)) return cp;
  let u16 = 0;
  let seen = 0;
  for (const ch of text) {
    if (seen >= cp) return u16;
    u16 += ch.length;
    seen++;
  }
  return text.length;
}

/** Convert a UTF-16 offset into `text` to a code-point offset (GDScript String index). Negative
 *  offsets pass through; offsets past the end clamp to the code-point length. */
export function utf16ToCp(text: string, u16: number): number {
  if (u16 <= 0 || !HAS_ASTRAL.test(text)) return u16;
  let at = 0;
  let cp = 0;
  for (const ch of text) {
    if (at >= u16) return cp;
    at += ch.length;
    cp++;
  }
  return cp;
}
