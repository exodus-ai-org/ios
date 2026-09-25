# iOS Rich Tool Cards Implementation Plan

> For agentic workers: executed one task at a time (iOS tasks share one project + DerivedData — never two at once),
> each followed by an independent review. Steps are checkboxes.

**Goal:** replace the generic JSON card with real cards for the tools and memory items in the spec.
**Spec:** `docs/superpowers/specs/2026-09-25-ios-rich-tool-cards-design.md`. Prototypes (DEBUG) in
`Sources/ChatFeature/Prototypes/` are the visual reference and fixture source — promote code from them, don't rewrite.

## Global Constraints

The shared brief `ios-B-global.md` (session scratchpad) applies: no commits except a `Vendor/exodus-locales` subtree
sync (owner-allowed), catalog keys in 10 languages, audit exit 0, Swift 6 strict concurrency, own scratch simulator
(never "iPhone 17"/"iPhone 17e"), Debug + Release builds, mutation checks. Plus: decoding off the render path; the
`AssistantTurnView` Equatable contract holds; undecodable details → generic card + `LogReporter`.

## Tasks

- [ ] **C0 Card infrastructure.** A card registry keyed by tool name used by `ThinkingTimeline`/`ToolCardViews`;
  typed decoders (`Models`) for every result shape in the spec table; the run-foot slot in `AssistantTurnView` for
  memory items and search media; subtree sync of desktop locales for the `chat:` card keys (the only commit). Tests:
  decoders over the prototype fixtures, fallback to the generic card, render-count guard.
- [ ] **C1 File cards** — read/write/edit incl. the LCS unified diff (from the prototype) and the ≥3-edits collapse.
- [ ] **C2 Weather** — Swift Charts curve, 3 days, Details in place.
- [ ] **C3 Image generation** — Metal-shader forming effect (+ reduced motion), image loading through the paired
  session from the desktop media route (shape from the desktop report `desktop-media-report.md`), zoom, legacy rows.
- [ ] **C4 Map itinerary** — MapKit markers + per-day polylines, stop list, full-screen map (page or sheet), place
  detail, `notice`.
- [ ] **C5 Web search media** — image grid + video cards at the run foot.
- [ ] **C6 Computer use** — live frame while running (frames kept per session during the stream), filmstrip when done,
  awaitingHuman state.
- [ ] **C7 Deep research** — progress while streaming, report preview, full report view (markdown via MarkdownKit).
- [ ] **C8 Memory** — strip (running/done/undo/undone/partial/stale/failed/partly) with `POST /memory/undo`; used-
  memories line + sheet; "This is wrong" → composer prefill + focus; SSE `memories_used` + `GET /memory/usage`.
- [ ] **C9 Final review + polish** — whole-feature review (opus), fix wave, prototypes page kept DEBUG-only.
