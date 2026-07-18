// file://-URI -> a local filesystem path (used by the workspace index + go-to-definition to read
// unopened files). Formatting is now fully in-process (formatGuitkx.ts) — no Godot binary needed.

export function uriToProjectPath(rootUri: string): string {
  if (!rootUri) return "";
  // Strip scheme + authority separator (TWO slashes), preserving the path's leading slash. On POSIX
  // `file:///tmp/x` -> `/tmp/x` (absolute); on Windows `file:///c:/x` -> `/c:/x`, whose leading slash
  // is then dropped for the drive-letter form only. Stripping all three slashes broke POSIX. [audit]
  let p = decodeURIComponent(rootUri.replace(/^file:\/\//, ""));
  if (/^\/[A-Za-z]:(\/|$)/.test(p)) p = p.slice(1);
  return p;
}
