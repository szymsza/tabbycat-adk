# Side Locks: editable side pre-allocation on `/admin/draw/sides`

Branch: `side-locks-edits` (off `adk-debatovani-upgraded`).

## 1. Summary

Tabbycat already has a page at `/admin/<tournament>/draw/sides/` ("Side
Pre-Allocations") but it is **read-only**: a grid of team × round showing
whatever is in the `TeamSideAllocation` table. This plan upgrades that page
so tab room staff can:

1. Manually set/change a team's side **pre-allocation** for the next
   round to be drawn (a per-team dropdown, format-aware naming).
2. See, for already-drawn rounds, the team's **actual** side (from
   `DebateTeam.side`) instead of the (now largely irrelevant) pre-allocation.
3. Bulk-populate the next round's pre-allocations from any earlier
   finished round in one action — "same as" or "opposite of" — instead of
   setting every team by hand. This is the main time-saver: e.g. "everyone
   who was Proposition in round 3, make them Opposition in round 5."

This is scoped to be a small, self-contained, mainline-mergeable change: no
new preferences, no new permissions, no changes to the draw generation
algorithm itself, reuses the existing model and existing patterns for
editable admin tables.

## 2. Terminology (confirmed against the codebase)

- **Pre-allocation** = `draw.models.TeamSideAllocation` (`round`, `team`,
  `side`, unique per round+team). Purely a planning record. It is only
  consumed by the draw generator when the tournament preference
  `draw_side_allocations` (`options/preferences.py`, `DrawSideAllocations`)
  is set to `'preallocated'` — see `DrawManager._populate_team_side_allocations()`
  (`draw/manager.py`), which reads it and stashes `team.allocated_side` for
  the generator (`draw/generator/common.py`, `draw/generator/__init__.py`).
  Under any other setting (`random`, `balance`, `manual-ballot`),
  `TeamSideAllocation` rows are never read by draw generation.
- **Actual/real allocation** = `draw.models.DebateTeam.side`, set once a
  `Debate`/`DebateTeam` exists for a round (i.e. once a draw has been
  generated for that round). This is authoritative and doesn't change
  unless the draw itself is edited/regenerated.
- These are already exactly the two different things you described —
  nothing to reconcile, the model split already exists.

## 3. Current state (what exists today, unmodified)

- `draw/urls_admin.py`: `path('sides/', views.SideAllocationsView.as_view(), name='draw-side-allocations')`.
- `draw/views.py`:
  - `BaseSideAllocationsView(TournamentMixin, VueTableTemplateView)` —
    builds a `TabbycatTableBuilder` table: rows = `tournament.team_set.all()`,
    columns = `tournament.prelim_rounds()`, cells = pre-allocation abbreviation
    or `"—"`. No update endpoint exists.
  - `SideAllocationsView(AdministratorMixin, BaseSideAllocationsView)` —
    `view_permission = Permission.EDIT_ALLOCATESIDES`. This is the
    permission we'll reuse for the new edit endpoints too (no new permission
    needed).
  - `PublicSideAllocationsView(PublicTournamentPageMixin, BaseSideAllocationsView)` —
    public read-only mirror, gated by the `public_side_allocations`
    preference. **Out of scope for editing** — stays read-only.
- `templates/nav/admin_nav.html`: the "Sides" nav link is only rendered
  `{% if pref.draw_side_allocations == 'preallocated' %}`. **This existing
  gating is preserved as-is** — the feature stays invisible in the UI for
  any tournament not using pre-allocated sides, exactly as it is today. We
  will not add a separate in-page warning banner; the nav gate already does
  the job.
- Side naming: `tournaments/utils.py::get_side_name(tournament, side, name_type)`.
  - 2-team tournaments: looks up `SIDE_NAMES[tournament.pref('side_names')]`
    — configurable choice of Aff/Neg, Gov/Opp, Prop/Opp, Pro/Con,
    Appellant/Respondent, or "1"/"2". `side` is `0` or `1`
    (`draw.types.DebateSide.AFF`/`NEG`).
  - 4-team (BP) tournaments: fixed `BP_SIDE_NAMES` — `0`=Opening Government
    (OG), `1`=Opening Opposition (OO), `2`=Closing Government (CG),
    `3`=Closing Opposition (CO). Not configurable, only `name_type`
    (`full`/`team`/`abbr`) varies.
  - `side == -1` (bye) already returns `gettext('bye')`.
  - This function already does everything item 3 of your original ask
    needs — the dropdown just needs to iterate `tournament.sides` and label
    each option with `get_side_name(tournament, side, 'full')`.
- Draw status gating: a round has no `TeamSideAllocation` effect once its
  draw exists. `Round.Status`: `NONE → DRAFT → CONFIRMED → RELEASED`.
  `DrawManager.create()` raises if `draw_status != NONE`. There is no
  "recompute sides only" path — changing a pre-allocation after a draw
  exists does nothing until the draw is deleted (`ConfirmDrawRegenerationView`)
  and regenerated.

## 4. Decisions (confirmed with you)

| Question | Decision |
|---|---|
| Which rounds are shown/editable? | **Primary**: the current round (next round without a draw) must be editable. **Stretch, optional**: rounds further ahead that also have no draw yet. Rounds that already have a draft/confirmed draw are always shown as read-only actual sides, never editable. |
| Editing a round that's already drawn | **Blocked.** That round's cell shows the real `DebateTeam.side` (read-only), not an editable control. |
| Bulk "opposite" rule for BP (4 sides) | OG↔CO, OO↔CG. This generalizes cleanly with 2-team Aff↔Neg as a single formula (see §6). |
| Bulk tool scope | **General tool**, not hardcoded to "N-2": pick any earlier finished round as the source, and a Same/Opposite toggle. |
| Bulk tool target | **All teams at once**, one click — this is the main value-add. |
| Bult tool + byes | If a team had a bye in the chosen source round (no `DebateTeam` row that round), **skip that team** — leave their pre-allocation as-is for manual resolution. Report the skip count in the result message. |
| Preference gating | Page stays hidden from nav unless `draw_side_allocations == 'preallocated'`, exactly as today. No extra warning banner needed. |
| Elimination rounds | **Out of scope.** Preliminary rounds only (`tournament.prelim_rounds()`, matching the existing read-only page). |
| Rounds beyond current | Documented as an optional stretch section (§9), not required for v1. |

## 5. UI design

Extend the existing `/admin/draw/sides/` page (same URL, same nav entry,
same page title "Side Pre-Allocations") rather than adding a new page.

**Matrix**, unchanged shape (rows = teams, columns = preliminary rounds),
but each column now renders one of three states:

1. **Already-drawn round** (`round.draw_status` in `DRAFT`, `CONFIRMED`,
   `RELEASED`): read-only cell showing the team's actual side that round,
   via `get_side_name(tournament, debateteam.side, 'abbr')` pulled from
   `DebateTeam`. Byes show "—".
2. **The current round** (first round with `draw_status == NONE`,
   i.e. `tournament.current_round` if that's undrawn, else the next
   undrawn round): **editable dropdown**, one option per `tournament.sides`
   value (labelled via `get_side_name(tournament, side, 'full')`), plus an
   "Unallocated" option to clear. Backed by `TeamSideAllocation`.
3. **Future undrawn rounds** (stretch, §9): same editable dropdown as (2),
   included only if we build the stretch scope.

**Bulk tool** ("Side Locks" bulk-apply), shown once, above the table:

```
Set pre-allocations for: [ dropdown: any not-yet-drawn preliminary round ]
Copy from:                [ dropdown: any earlier finished round ]
Direction:                ( ) Same as that round   ( ) Opposite of that round
                           [ Apply to all teams ]
```

The target-round dropdown defaults to the immediately-next undrawn round
(the one editable inline in the matrix) but can be pointed at any further
undrawn round too.

A short paragraph above the tool explains the matrix's two display modes:
rounds with a draw already show each team's actual side; rounds without one
yet show the (editable, for the next round) pre-allocation.

Clicking "Apply" POSTs once, shows a confirmation dialog first (it
overwrites existing pre-allocations for every team in the target round —
this is a bulk destructive-to-current-state action on planning data, so a
confirm step matches how other bulk actions in Tabbycat behave, e.g. draw
regeneration), then refreshes the table and reports e.g. "Set 22 teams,
skipped 2 (had a bye in round 3)."

## 6. "Opposite" formula

For both 2-team and BP, the confirmed opposite mapping is exactly:

```python
def opposite_side(side: int, teams_in_debate: int) -> int:
    return teams_in_debate - 1 - side
```

- 2-team: `opposite(AFF=0) = 1 = NEG`, `opposite(NEG=1) = 0 = AFF`. ✓
- BP: `opposite(OG=0) = 3 = CO`, `opposite(OO=1) = 2 = CG`,
  `opposite(CG=2) = 1 = OO`, `opposite(CO=3) = 0 = OG`. ✓ matches the
  confirmed OG↔CO / OO↔CG rule exactly.

One formula, no per-format branching needed in the bulk-apply logic.

## 7. Backend implementation

No new Django models or migrations. No new preference, no new permission
(`Permission.EDIT_ALLOCATESIDES` already exists and already gates the
current admin page).

**One new `ActionLogEntry.ActionType`** (`actionlog/models.py`), following
the existing `SIDES_SAVE` / `AVAIL_TEAMS_SAVE` convention:

```python
SIDE_PREALLOCATIONS_SAVE = 'sa.save', _("Edited side pre-allocations")
```

**`draw/views.py` changes:**

- `BaseSideAllocationsView.get_table()`: extend to branch per-column as
  described in §5 — for drawn rounds pull `DebateTeam` sides, for the
  editable round(s) emit a cell dict with `'component': 'side-cell'`
  carrying `{team_id, round_id, value, options: [{value, label}, ...], saveURL}`,
  mirroring how `AvailabilityTypeBase.get_table()` builds `check-cell`
  cells today (`availability/views.py`).
- New `UpdateSidePreallocationView(AdministratorMixin, LogActionMixin, View)`
  — `edit_permission = Permission.EDIT_ALLOCATESIDES`, `POST` body
  `{team_id, round_id, side}` (`side: null` clears the row), guards that
  `round.draw_status == Round.Status.NONE` (403/400 otherwise — defence in
  depth, the frontend won't offer the control for drawn rounds anyway),
  `TeamSideAllocation.objects.update_or_create(...)` or `.delete()` if
  cleared. Mirrors `BaseAvailabilityUpdateView.post()`.
- New `BulkApplySidePreallocationView(AdministratorMixin, LogActionMixin, PostOnlyRedirectView)`
  — same permission. Implemented as a plain synchronous form POST (not a
  JSON/AJAX endpoint like the single-cell update above) since it doesn't
  need to update the table in place — a normal Django `messages.success`/
  `messages.error` + redirect back to the sides page is simpler and matches
  the convention already used by the rest of `draw/views.py` for one-shot
  admin actions (e.g. `SetRoundStartTimeView`, `ConfirmDrawRegenerationView`).
  `POST` body (regular form fields) `{target_round_id, source_round_id, direction}`
  (`direction` is `'same'` or `'opposite'`). Validates
  `target_round.draw_status == NONE` and `source_round.draw_status in
  (CONFIRMED, TEAMS_RELEASED, RELEASED)` (must be an actually finished round
  — draft rounds' sides could still change). For each team: look up its
  `DebateTeam` for `source_round` via a single bulk `values_list('team_id', 'side')`
  query; if missing (bye or team wasn't in that round) or the side is
  `DebateSide.BYE`, skip and count it; else compute `side = dt.side` or
  `opposite_side(dt.side, tournament.pref('teams_in_debate'))` and
  `update_or_create` the target round's `TeamSideAllocation`. Reports
  applied/skipped counts via a `messages.success` banner.
- `draw/urls_admin.py`: two new routes for the update views, e.g.
  `sides/update/` and `sides/bulk/`.

## 8. Frontend implementation

- New `templates/tables/SideCell.vue`, modelled directly on
  `templates/tables/CheckCell.vue` (uses the same `AjaxMixin.ajaxSave`
  pattern) but rendering a `<select>` instead of a checkbox, emitting on
  `@change`.
- Register it in `templates/tables/SmartTable.vue` next to `CheckCell`
  (`components: { ..., SideCell }`) so `cellData.component: 'side-cell'`
  resolves.
- Bulk tool: a plain server-rendered `<form>` (new template
  `draw/templates/side_allocations.html`, extending `tables/base_vue_table.html`
  and overriding `content` to add the form above `{{ block.super }}`) — no
  new Vue component needed, since it's a one-shot action with a full
  redirect-back afterwards rather than an in-place table update. Only
  rendered when there's an undrawn round to target and at least one
  finished prior round to copy from; the submit button is guarded by a
  native `confirm()` dialog since it overwrites existing pre-allocations
  for every team in the target round.

## 9. Stretch (optional, not required for v1)

Extending the editable-dropdown treatment (state 2 in §5) to *all*
not-yet-drawn rounds, not just the immediate next one — useful for tab
teams that like to plan side balance several rounds ahead. Purely additive
on top of the v1 design (same cell component, same update endpoint, just a
looser "which columns are editable" condition), so it can land in a
follow-up PR without touching v1's shape.

**Partially implemented** (post-v1 follow-up, same PR): the bulk-apply
tool's target round is now a `<select>` (`target_round_choices` in
`SideAllocationsView.get_context_data()`) listing *every* not-yet-drawn
preliminary round, not just the immediate next one — `BulkApplySidePreallocationView`
never actually hardcoded the target round server-side, so this only
required a template change. A further undrawn round's cell in the matrix
is still not inline-editable (that's still the stretch item above), but if
a pre-allocation exists for it (e.g. set via the bulk tool) it's now shown
read-only in the matrix instead of always "—".

## 10. Edge cases

- **Bye in the source round of a bulk apply**: skip, don't touch that
  team's existing pre-allocation, count it in the response message (per
  your decision — resolved manually).
- **Team added mid-tournament** with no `DebateTeam` row in the source
  round: same skip path as a bye, no special-casing needed.
- **Clearing a pre-allocation**: dropdown includes an explicit "Unallocated"
  option that deletes the `TeamSideAllocation` row rather than writing an
  invalid side value.
- **Direct URL access when `draw_side_allocations != 'preallocated'`**:
  today the page itself isn't gated on this (only the nav link is). Minor
  incidental hardening worth doing while we're in this view: add the same
  check to `SideAllocationsView`/the two new POST views so a stale
  bookmark or link can't silently edit pre-allocations that the draw
  generator will never read.
- **Round with `teams_in_debate` other than 2 or 4**: not currently
  possible in Tabbycat (`Tournament.sides` only defines those two cases) —
  no handling needed beyond what already exists.

## 11. Testing plan

- `opposite_side()`: unit tests for both 2-team and BP mappings.
- `BulkApplySidePreallocationView`: bye/missing-`DebateTeam` skip behaviour,
  same-vs-opposite correctness, rejection when target round already drawn,
  rejection when source round isn't finished, permission check.
- `UpdateSidePreallocationView`: set, clear, rejection when round already
  drawn, permission check.
- `BaseSideAllocationsView.get_table()`: correct column state (read-only
  vs editable) per round's `draw_status`; correct side-name labels for a
  2-team tournament under a couple of `side_names` settings and for a
  4-team (BP) tournament.
- Manual verification via the local Docker deployment against a real
  multi-round tournament fixture, same workflow used for the KPDP features.

## 12. Mainline-mergeability checklist

- No new preferences or permissions.
- No schema changes (reuses `TeamSideAllocation` as-is).
- One additive `ActionLogEntry.ActionType` (backwards-compatible enum
  addition).
- New Vue component follows the existing `CheckCell.vue`/`AjaxMixin`
  convention exactly, no new frontend architecture introduced.
- All new UI strings wrapped for translation, matching the rest of the
  page.
- Existing read-only public page (`PublicSideAllocationsView`) untouched.
- Existing nav-gating behaviour (`draw_side_allocations == 'preallocated'`)
  untouched.

## 13. Suggested sequencing

1. Backend: `opposite_side()` helper + `ActionLogEntry` addition + the two
   new views + URL routes, with unit tests. No UI changes yet — testable
   headless.
2. Frontend: `SideCell.vue`, wire into `SmartTable.vue`, extend
   `get_table()` to emit editable cells for the current round only, single-
   cell save working end to end.
3. Bulk tool UI + wiring to `BulkApplySidePreallocationView`.
4. Manual verification against a real tournament (both a 2-team and a BP
   tournament, to exercise both side-naming paths).
5. (Optional, separate PR) §9 stretch: extend editable range beyond the
   current round.
