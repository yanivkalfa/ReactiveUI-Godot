// Reads the compiler's diagnostics sidecar (Foo.guitkx.diags.json, written by guitkx_codegen.gd) so
// the LSP can surface the compiler's FULL diagnostic catalog in VS Code without a running editor.
// Gated by a source hash: if the open buffer no longer matches the last-compiled source, the sidecar
// is stale and suppressed (it reappears on the next save+compile). srcHash MUST stay identical to
// RUIGuitkxCodegen.src_hash (FNV-1a over code points).

import { readFileSync } from "fs";

export interface SidecarDiag {
  code: string;
  severity: string; // "error" | "warning"
  message: string;
}
export interface Sidecar {
  src_hash: number;
  diagnostics: SidecarDiag[];
}

export function srcHash(s: string): number {
  let h = 2166136261;
  // iterate by CODE POINT (for…of) to mirror Godot's unicode_at over String.length() code points —
  // identical to charCodeAt for BMP, but correct for astral-plane chars too.
  for (const ch of s) {
    h = (h ^ ch.codePointAt(0)!) >>> 0;
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}

export function readSidecar(guitkxFsPath: string): Sidecar | null {
  try {
    const j = JSON.parse(readFileSync(guitkxFsPath + ".diags.json", "utf8"));
    if (typeof j.src_hash === "number" && Array.isArray(j.diagnostics)) return j;
  } catch {
    /* missing / unreadable */
  }
  return null;
}
