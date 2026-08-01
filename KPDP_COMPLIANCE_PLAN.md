# KPDP Compliance — Development Plan

Branch: `kpdp-compliance` (off `adk-debatovani-upgraded`)

This document plans two independent, preference-gated changes needed to make
Tabbycat compliant with KPDP (Czech debate format) rules:

- **Feature A** — median (instead of mean) aggregation of panel speaker/team
  scores.
- **Feature B** — allowing a solo adjudicator to record a self-declared 2:1
  "split" decision.

Both are additive and gated behind new tournament preferences, so tournaments
not using KPDP rules are unaffected by default.

Neither feature has been implemented yet — this document is the plan only.

---

## Feature A — Median scoring for panels

### Problem

When a panel of adjudicators judges a debate, Tabbycat currently aggregates
each judge's scores into the final recorded score using the arithmetic mean.
KPDP rules require the **median** of all judges' scores instead.

### Current behavior (as implemented today)

All aggregation happens in `tabbycat/results/result.py`, in
`DebateResultByAdjudicatorWithScores` (the class used when a tournament's
`ballots_per_debate` preference is `'per-adj'`, i.e. one scoresheet per
voting adjudicator). Three methods compute an aggregate with
`statistics.mean` (imported at the top of the file) and the result is
persisted once, at ballot-save time, into the corresponding model field:

| Method | Line (approx) | Persisted to |
|---|---|---|
| `teamscore_field_score(self, side)` | ~1166 | `TeamScore.score` |
| `speakerscore_field_score(self, side, position)` | ~1181 | `SpeakerScore.score` |
| `speakercriterionscore_field_score(self, side, pos, criterion)` | ~1189 | `SpeakerCriterionScore.score` |

All three follow the same pattern:

```python
def speakerscore_field_score(self, side, position):
    if not self.is_complete():
        return None
    return mean(self.scoresheets[adj].get_score(side, position)
                for adj in self.relevant_adjudicators())
```

`relevant_adjudicators()` (line ~578) decides **which** judges' scoresheets
are included in the aggregate:

```python
def relevant_adjudicators(self):
    if self.tournament.pref('margin_includes_dissenters'):
        return self.scoresheets.keys()
    else:
        return self.majority_adjudicators()
```

This is controlled by the existing `MarginIncludesDissent` preference
(`options/preferences.py`, `scoring` section): when off (the default), only
adjudicators who voted with the majority winner are included; when on, all
adjudicators are included.

Nothing downstream recomputes an average — standings, the tab, and the
public results pages all just read the already-aggregated `score` field. So
this change only needs to happen at the three save-time call sites above.

**Decision (confirmed with user):** KPDP's median aggregation should
**respect** the existing `margin_includes_dissenters` preference rather than
always forcing "all judges". I.e. we are only swapping the aggregation
*function* (mean → median), not changing which judges are included.

**Decision (confirmed with user):** Both team scores (`TeamScore.score`) and
individual speaker scores (`SpeakerScore.score`) should use median — not
just speaker scores. Since both flow through the same `mean(...)` pattern,
this falls out naturally from changing all three call sites consistently
(no reason to special-case team scoring separately).

**Decision (confirmed with user):** For an **even-sized panel**, where
there is no single middle value, fall back to the **mean of all relevant
adjudicators' scores, rounded up to the nearest whole number** (ceiling),
rather than Python's default even-length `statistics.median` behavior
(which averages the two middle values). KPDP panels are normally
odd-sized, so this fallback is expected to be rare in practice, but must be
implemented explicitly rather than left to `statistics.median`'s default.

**Decision (confirmed with user):** Use a `ChoicePreference` (not a
boolean) for the aggregation function, so the option reads clearly in the
tournament options UI and leaves room for future aggregation methods.

### Design

1. **New tournament preference** in `tabbycat/options/preferences.py`,
   `scoring` section, next to `MarginIncludesDissent`:

   ```python
   @tournament_preferences_registry.register
   class ScoreAggregationFunction(ChoicePreference):
       help_text = _("How to combine multiple adjudicators' scores into a "
           "single recorded score for a panel-judged debate. This affects "
           "SpeakerScore, TeamScore and SpeakerCriterionScore values (and, "
           "transitively, margins) for every panel-judged debate in this "
           "tournament — changing it recalculates results the next time "
           "each affected ballot is saved. 'Mean' averages all relevant "
           "adjudicators' scores. 'Median' (required by KPDP rules) uses "
           "the middle score for odd-sized panels; for even-sized panels, "
           "where there is no single middle value, it falls back to the "
           "mean, rounded up to the nearest whole number. Which "
           "adjudicators count as 'relevant' is still controlled "
           "separately by the 'Margin includes dissenting adjudicators' "
           "option above.")
       verbose_name = _("Panel score aggregation function")
       section = scoring
       name = 'score_aggregation_function'
       choices = (
           ('mean', _("Mean (average)")),
           ('median', _("Median")),
       )
       default = 'mean'
   ```

2. **Aggregator selection helper** on `DebateResultByAdjudicatorWithScores`:

   ```python
   def _score_aggregator(self):
       def median_or_rounded_up_mean(values):
           values = list(values)
           if len(values) % 2 == 1:
               return statistics.median(values)
           return math.ceil(statistics.mean(values))

       if self.tournament.pref('score_aggregation_function') == 'median':
           return median_or_rounded_up_mean
       return statistics.mean
   ```

   (Requires `import math` alongside the existing `statistics` import.)

3. Replace `mean(...)` with `self._score_aggregator()(...)` at the three
   call sites listed above.

4. **Margin** (`calculate_margin` / `calculate_full_margin`,
   `DebateResultWithScoresMixin`) needs **no direct change** — it is
   computed as `aff_total - neg_total` from the (now median-based) scores,
   so it inherits the new aggregation automatically.

5. **No database migration required.** `django-dynamic-preferences` is
   schema-less; registering a new preference class is sufficient.

### Testing plan

- Extend `tabbycat/results/tests/test_result.py` with cases mirroring the
  existing mean-aggregation tests, asserting median output for odd panels,
  and the rounded-up-mean fallback for even panels (e.g. a 4-judge panel
  with scores that produce a non-whole mean).
- Manual check: create a KPDP-preference tournament in the local Docker
  deployment, enter a 3-judge panel ballot with divergent scores, confirm
  `SpeakerScore.score` / `TeamScore.score` reflect the median, not the mean;
  repeat with a 4-judge panel to confirm the rounded-up-mean fallback.

### Effort estimate

Small — one preference, one helper method, three call-site edits, plus
tests. No schema change, no UI change (aggregation is invisible to the
adjudicator entering the ballot; it only affects the recorded/displayed
result).

---

## Feature B — Self-splitting solo judge (2:1 declared split)

### Problem

In KPDP format, even a solo-judged debate (one adjudicator, no panel) can
be recorded as a split decision — e.g. the adjudicator personally weighed
the debate as 2:1 to one team, similar to how a 3-judge panel might split.
The adjudicator should be able to flag this when entering the result. This
should feed into standings the same way a real panel split would.

### Current behavior (as implemented today)

There is **no existing concept** of a solo adjudicator declaring a split.
A solo-judged debate goes through `DebateResultByAdjudicator` /
`DebateResultByAdjudicatorWithScores` (`results/result.py`) with exactly one
adjudicator, so:

- `_calculate_decision()` (line ~540) trivially resolves the winner from
  that one scoresheet (`votes_aff`/`votes_neg` = 1/0 or 0/1).
- `teamscore_field_votes_given` / `teamscore_field_votes_possible`
  (line ~612-616) always resolve to `1`/`1` for a solo debate:

  ```python
  def teamscore_field_votes_given(self, side):
      return len(self._adjs_by_side[side])

  def teamscore_field_votes_possible(self, side):
      return len(self.scoresheets)
  ```

Importantly, **`TeamScore.votes_given` / `votes_possible` already exist as
model fields** (`results/models.py`, `TeamScore`, line ~330) and are
**already consumed by an existing standings metric**:
`NumberOfAdjudicatorsMetricAnnotator` (`tabbycat/standings/teams.py:302`,
public-facing name "votes/ballots carried"):

```python
def get_field(self):
    return (Cast('debateteam__teamscore__votes_given', FloatField()) /
        NullIf('debateteam__teamscore__votes_possible', 0, output_field=FloatField()) *
        self.adjs_per_debate)
```

This metric normalizes `votes_given / votes_possible` to a configurable
"typical panel size" (`adjs_per_debate`, default 3) for standings/tiebreaker
purposes. A parallel version exists for speaker standings in
`tabbycat/standings/speakers.py:148`.

This means the data model and standings machinery for "partial ballots"
already exist — they're just never populated with anything other than
`1/1` (solo) or the judge count (real panels). Feature B's job is to let a
solo adjudicator populate them as `2/3` instead.

**Decision (confirmed with user):** The self-split is always a simple
binary flag — "this was a 2:1 split in favor of the declared winner" —
not a fully custom vote breakdown. **Decision (confirmed with user):** the
target ballot entry mode for solo debates is `'per-adj'`
(`PerAdjudicatorBallotSetForm`), not consensus/`'per-debate'` mode.
**Decision (confirmed with user):** this should feed into points/standings,
not just be a display annotation — which the existing "votes/ballots
carried" metric already gives us, once populated correctly.

### Design

1. **New model field** on `BallotSubmission`
   (`tabbycat/results/models.py`):

   ```python
   self_split = models.BooleanField(default=False,
       verbose_name=_("self-declared split decision"),
       help_text=_("For solo-adjudicated debates: whether the adjudicator "
           "is declaring this decision as a 2:1 split rather than a "
           "unanimous 3:0/1:0, per KPDP rules."))
   ```

   Requires a new migration in `results/migrations/`.

2. **New tournament preference**, `data_entry` section
   (`options/preferences.py`), next to `SplitVotingBallots`:

   ```python
   @tournament_preferences_registry.register
   class AllowSelfSplitBallots(BooleanPreference):
       help_text = _("Allow a solo adjudicator to declare their decision "
           "as a 2:1 split, per KPDP rules.")
       verbose_name = _("Allow self-split ballots for solo adjudicators")
       section = data_entry
       name = 'allow_self_split_ballots'
       default = False
   ```

3. **Form change** — `PerAdjudicatorBallotSetForm`
   (`tabbycat/results/forms.py`, line ~893): when the ballot has exactly one
   voting adjudicator *and* `allow_self_split_ballots` is on, add a checkbox
   field (e.g. `self_split`) alongside that adjudicator's declared-winner
   dropdown. Wire it into `create_score_fields`, `initial_from_result`, and
   the save path (`clean_scoresheet` / wherever `BallotSubmission` fields
   are persisted) so it round-trips like other ballot fields.

4. **Result calculation override** — in `result.py`, override
   `teamscore_field_votes_given` / `teamscore_field_votes_possible` (or add
   a subclass branch) so that when `len(self.scoresheets) == 1` and
   `self.ballotsub.self_split` is true:
   - Winning side: `votes_given=2, votes_possible=3`
   - Losing side: `votes_given=1, votes_possible=3`

   Everything else (declared winner, scores, margin) is untouched — those
   already come from the one real scoresheet as today.

5. **Standings**: no code change required for points/tiebreaker purposes —
   once `votes_given`/`votes_possible` are populated correctly, a tournament
   that adds "votes/ballots carried" (`num_adjs`) to its standings metrics
   will automatically reflect self-split solo debates as partial ballots,
   consistent with how real panel splits are already handled.

6. **Display** — `adjudicators_with_splits()` (`result.py`, line ~631) and
   the ballot tables that render split information (`utils/tables.py:602`)
   currently assume splits only occur on real multi-adjudicator panels, and
   are gated by the existing `ShowSplittingAdjudicators`
   (`show_splitting_adjudicators`) preference.

   **Decision (confirmed with user):** reuse that same existing
   `show_splitting_adjudicators` preference/toggle to also control
   visibility of the self-split flag, rather than introducing a separate
   visibility setting. Concretely: wherever real panel splits are currently
   shown at adjudicator-facing results (the same views/tables driven by
   `adjudicators_with_splits()` / `utils/tables.py:602`), a solo self-split
   ballot should render an equivalent "2:1 (self-declared)" indicator when
   `show_splitting_adjudicators` is on. This is intentionally symmetric
   with how real splits are surfaced today, and doubles as the easiest way
   to manually verify the feature end-to-end (see Testing plan below) since
   the flag becomes visible directly on the results view instead of only
   being inferable from standings.

### Resolved: ballot-entry UI architecture

Tabbycat has two parallel UI generations for ballot entry. The
adjudicator-facing self-entry page (`BasePublicNewBallotSetView`,
`results/views.py:541`, template `public_enter_results.html` →
`ballot/ballot_set.html`) — i.e. the page a solo adjudicator actually
uses — is **plain server-rendered Django templates**, not Vue. The
existing `declared_winner` dropdown already round-trips end-to-end through
this exact path (`forms.py` field → `ballot/ballot_set.html:75-79` →
normal POST), so adding a checkbox alongside it is a small, well-trodden
change: one more form field + one more `{% include %}` line, no
JS/frontend framework work required. The old admin/assistant UIs
(`enter_results.html`, `assistant_enter_results.html`) share the same
`ballot/ballot_set.html` partial, so they get the checkbox for free too.

The newer "beta" admin/assistant Vue UI (`ballot_entry.html` +
`BallotEntryContainer.vue`) does **not** currently wire up `declared_winner`
at all (it's not present in the Vue mirror-form markup) — this is a
pre-existing gap unrelated to this feature. Decision: ship the self-split
checkbox for the classic/public UI only, consistent with how
`declared_winner` already behaves; do not attempt to add it to the beta
Vue UI as part of this feature.

Exact preference section/name and model field name (`self_split` used
above) are finalized in the Design section as implemented.

### Testing plan

- Model/migration test: `BallotSubmission.self_split` round-trips via the
  admin and via `manage.py migrate`.
- `results/tests/test_result.py`: solo-adjudicator ballot with
  `self_split=True` produces `votes_given=2, votes_possible=3` for the
  winner and `1/3` for the loser; `self_split=False` (default) still
  produces `1/1` as today (regression check).
- `standings/tests/test_standings.py`: a tournament with the "votes/ballots
  carried" metric enabled correctly ranks/ties teams based on self-split
  solo results, mirroring the existing real-panel-split test cases.
- Manual check in local Docker deployment: enable both
  `allow_self_split_ballots` and `show_splitting_adjudicators` on a test
  tournament, enter a solo ballot with the split checkbox ticked, and
  confirm two things directly rather than only inferring from standings:
  (a) the adjudicator-facing results view shows the "2:1 (self-declared)"
  indicator, the same way a real panel split would be shown; (b) the
  standings page reflects a partial ballot for the losing team.

### Effort estimate

Medium — new field + migration, new preference, form changes (scope
depends on the Django-vs-Vue finding above), a small result-calculation
override, and a couple of display tweaks. Larger than Feature A but still
contained; no changes needed to the standings calculation engine itself
since it already supports partial ballots.

---

## Suggested sequencing

1. **Feature A first** — smaller, fully backend/data-layer, no schema
   change, no UI change. Good to ship and verify independently.
2. **Feature B second** — builds on the same "add a KPDP preference"
   pattern established in Feature A, but touches more surface area (schema,
   forms, possibly Vue, display). Confirm the Django-vs-Vue question early
   in this phase since it changes the effort estimate materially.

Both features are independent of each other and can be developed/reviewed
as separate PRs against `kpdp-compliance` (or merged into it sequentially).

## Non-goals / explicitly out of scope for this plan

- Changing win/loss determination logic (majority vote + chair casting
  vote tiebreak) — unaffected by either feature.
- Changing how real (non-solo) panel splits are calculated or displayed —
  Feature B only adds the *solo* case; existing panel-split behavior is
  reused, not modified.
- Any change to non-KPDP tournaments' default behavior — both features are
  off by default via new preferences.
