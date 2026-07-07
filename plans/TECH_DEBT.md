# ReactiveUI — Technical Debt Register

Known, deliberately-unfixed defects across the ReactiveUI family (the Godot port here and the
upstream C#/Unity ReactiveUIToolKit). Each entry names the root cause, the reason it's still open,
and what a production-grade fix looks like — so a future fix starts from evidence, not rediscovery.

---

## TD-01 — Child reconciliation is an all-or-nothing gate, not React's per-child algorithm

**Where:** Unity `Shared/Core/Fiber/FiberChildReconciliation.cs:50` (the gate) and
`CanReuseFiber` at `:249-254` (type-only reuse). Godot analogue: `_any_keyed` at
`addons/reactive_ui/core/reconciler.gd:1006`.

**The defect (Unity).** The decision between keyed and index reconciliation is made **once for the
whole sibling set by sniffing only the first child's key**:

```csharp
// Check first child for keys (React convention: all-or-nothing keyed within a sibling set)
if (newChildren.Count > 0 && !string.IsNullOrEmpty(newChildren[0]?.Key))
    ReconcileChildrenWithKeys(...);   // whole list keyed
else
    ReconcileChildrenByIndex(...);    // whole list by position; keys NEVER read
```

The comment misattributes this to React. "All children keyed or none" is a **dev-time lint
guideline** (React only *warns*); it is **not** how React's runtime reconciles. React's
`reconcileChildrenArray` is **per-child, two-pass**: (1) a lockstep pass that reuses by position
only while keys match and **breaks on the first key mismatch**, then (2) a map pass that matches
the remaining tail by `key ?? index`. Unity's file already contains both halves
(`ReconcileChildrenByIndex` ≈ pass 1, `ReconcileChildrenWithKeys` ≈ pass 2) but **branches to one
or the other** instead of running them in sequence — and its index half is weaker than React's
pass 1 because `CanReuseFiber` checks **type only, never key**.

**Failure mode.** A mixed sibling list whose **first child is unkeyed but later children are
keyed** routes the entire list to the index path, so the keyed children are reconciled **by
position with their keys ignored**. On reorder, a fiber's state/focus/animation is handed to
whatever child now sits at its slot — **identity silently lost**. (The inverse — first child
keyed, rest unkeyed — routes all to the keyed path, giving unkeyed children synthetic index keys.)

**Why it is load-bearing (do not "just fix" it).** The Unity DoomGame sample's 3D viewport is
exactly this shape: an **unkeyed Sky at index 0** followed by **keyed floor/ceiling bands** whose
key embeds a per-frame-changing `SlabId`. Because of the first-child gate those keys are never
read, so the bands reconcile by slot and reuse in place — smooth. **Fix the reconciler to be
truly per-child React and the bands' changing `SlabId` keys start getting honored: key mismatch
every frame → delete + recreate → churn. Same ~186 nodes/frame we hit in Godot. So the core bug
is load-bearing for Doom's performance — the sample is fast *because* the reconciler is broken.**
"react-unity would be even faster if the bug were fixed" is backwards: **fixing it makes Doom
slower**, and you'd then need the structural hardening on top just to get back to where it is now.

**Godot port status (different, safer approximation).** Godot's gate is `_any_keyed` — **any**
keyed child promotes the whole list to the keyed path (unkeyed siblings get index-fallback keys).
This is still all-or-nothing, not true per-child React, but it errs toward **honoring** keys
rather than **dropping** them, so it cannot silently lose a keyed child's identity the way Unity's
gate does. This is precisely why the identical markup **churned in Godot but not Unity**, and it's
documented as a faithful-port divergence. The Godot Doom port is hardened structurally (isolated
unkeyed containers per band group) so it does not depend on the gate for performance.

**Production-grade fix (applies to either core).** Stop gating and implement React's actual
`reconcileChildrenArray`: run the lockstep-with-key-break pass, then the map pass for the tail,
**per child**. The pieces already exist in the Unity file; it's a matter of sequencing them
instead of branching. **Caveats:** it's a separate repo (Unity), it's a meaningful rewrite of the
hottest path in the reconciler, and — per the load-bearing note above — **landing it alone
regresses the Doom sample**, so it'd have to ship together with the sample hardening (drop the
`SlabId` identity from the band keys, or isolate the band lists into their own unkeyed containers,
the same fix applied in the Godot port).

**Status:** open / accepted. No observed bug is driving it in either port today (Godot's gate
fails safe; Unity's is masked by the sample shape). Track before any reconciler rewrite so the
Doom perf regression is anticipated, not discovered.
