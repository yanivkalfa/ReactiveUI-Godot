// Shared React-event <-> Godot-signal vocabulary for guitkx markup intelligence. This is the single
// source of truth the LSP uses so completion, hover, signature help, validation and semantic tokens
// all speak the SAME canonical React event names the RUNTIME actually binds. It mirrors
// addons/reactive_ui/core/host_config.gd (_EVENT_ALIASES / _resolve_signal / _is_event / camel<->snake)
// — keep the two in lockstep.
//
// Two spellings are accepted everywhere:
//   • React camelCase (CANONICAL): onClick, onChange, onSubmit, onInput, onFocus, onBlur,
//     onPointerDown/Up/Enter/Leave, onResize — plus any onXxxYyy that maps to the `xxx_yyy` signal.
//     `onChange` is polymorphic (React-style): it binds to whichever value/selection signal the class
//     actually has (item_selected / value_changed / text_changed / tab_changed / toggled).
//   • Native escape hatch: on_<signal> binds verbatim to "<signal>" (e.g. on_gui_input, on_id_pressed).

export interface SignalInfo {
  name: string;
  args: { name: string; type: string }[];
}

// React alias -> ordered candidate Godot signals. The FIRST candidate the class HAS wins, so one React
// name binds correctly across control types. Order matters: more-specific signals first so a Button
// subclass that also carries `toggled` (e.g. OptionButton) still binds onChange -> item_selected.
// Mirrors host_config.gd's _EVENT_ALIASES exactly (same names + order).
export const EVENT_ALIASES: Record<string, string[]> = {
  onClick: ["pressed"],
  onChange: ["item_selected", "value_changed", "text_changed", "tab_changed", "toggled"],
  onInput: ["text_changed"],
  onSubmit: ["text_submitted"],
  onFocus: ["focus_entered"],
  onBlur: ["focus_exited"],
  onPointerDown: ["button_down"],
  onPointerUp: ["button_up"],
  onPointerEnter: ["mouse_entered"],
  onPointerLeave: ["mouse_exited"],
  onResize: ["resized"],
};

const camelToSnake = (s: string): string =>
  s.replace(/([A-Z])/g, (_m, c: string, i: number) => (i ? "_" : "") + c.toLowerCase());

const snakeToPascal = (s: string): string =>
  s.replace(/(^|_)([a-z0-9])/g, (_m, _sep, c: string) => c.toUpperCase());

/** Is this attribute name an event handler (either convention)? Mirrors host_config._is_event. */
export function isEventAttr(name: string): boolean {
  if (name.startsWith("on_")) return true;
  return name.length > 2 && name.startsWith("on") && name[2] >= "A" && name[2] <= "Z";
}

/** The generic React camelCase name for a signal (onValueChanged for "value_changed"). */
export function reactNameForSignal(sig: string): string {
  return "on" + snakeToPascal(sig);
}

/** Resolve an event attr NAME to the underlying Godot signal, given a `has(signal)` membership test
 *  over the class's (base-flattened) signals. Mirrors host_config._resolve_signal. Returns undefined
 *  when the name is not an event attr at all. */
export function resolveSignalName(name: string, has: (sig: string) => boolean): string | undefined {
  if (name.startsWith("on_")) return name.slice(3);
  const cands = EVENT_ALIASES[name];
  if (cands) return cands.find((c) => has(c)) ?? cands[0];
  if (isEventAttr(name)) return camelToSnake(name.slice(2));
  return undefined;
}

export interface EventCompletion {
  label: string;
  signal: string;
  detail: string;
}

const signalDetail = (s: SignalInfo | undefined, sigName: string): string =>
  s ? `signal ${s.name}(${s.args.map((a) => `${a.name}: ${a.type}`).join(", ")})` : `signal ${sigName}`;

/** The React event completions to offer for a host class, given its (base-flattened) signals. Semantic
 *  aliases first (onClick / onChange / onSubmit / onFocus / onPointer* / …), then a generic onXxx for
 *  every non-private signal not already covered by a semantic alias. Private `_`-prefixed signals are
 *  skipped (internal). Each item carries the resolved signal + its signature for detail/docs. */
export function eventCompletionsFor(signals: SignalInfo[]): EventCompletion[] {
  const byName = new Map(signals.map((s) => [s.name, s]));
  const has = (s: string) => byName.has(s);
  const out: EventCompletion[] = [];
  const consumed = new Set<string>();
  for (const [alias, cands] of Object.entries(EVENT_ALIASES)) {
    const sig = cands.find((c) => has(c));
    if (sig) {
      out.push({ label: alias, signal: sig, detail: signalDetail(byName.get(sig), sig) });
      consumed.add(sig);
    }
  }
  for (const s of signals) {
    if (consumed.has(s.name) || s.name.startsWith("_")) continue;
    out.push({ label: reactNameForSignal(s.name), signal: s.name, detail: signalDetail(s, s.name) });
  }
  return out;
}

/** All valid event attr names for a host class (React canonical + the native on_<signal> escape hatch),
 *  for the unknown-attribute did-you-mean validation. */
export function validEventAttrs(signals: SignalInfo[]): string[] {
  const out = eventCompletionsFor(signals).map((c) => c.label);
  for (const s of signals) if (!s.name.startsWith("_")) out.push("on_" + s.name);
  return out;
}
