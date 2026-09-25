# QA Run Report: KDS-1, run 1

| Field | Value |
|---|---|
| Ticket | [KDS-1](https://fe-anysphere-demo.atlassian.net/browse/KDS-1): Temporal rules: support overnight time windows that cross midnight (e.g. 18:00-08:00) |
| Run | 1 (no earlier `qa/reports/KDS-1/run-*.md`) |
| Branch | `feature/temporal-rules-overnight-windows-qa-demo` (base `master`) |
| Commit under test | `81696dbb9f` |
| Triggered | Kevin Han, 2026-09-25T16:36:01Z (Ready for QA -> In QA) |
| Environment | OTP 22 (`/opt/otp22`), deps/ prebuilt, no install script run, setup about 1 min |
| Verdict | **FAIL**: 6 of 8 acceptance criteria fail (AC1, AC2, AC3, AC4, AC6, AC7). AC5 and AC8 pass. |
| Duration | About 50 min (16:36 to 17:26 UTC) |

## Plain-English summary

The overnight-window change works for most days of the month, but it has three serious problems.

1. On the 1st of every month, any overnight rule on a daily or weekly schedule crashes the routing step. The call then goes to the flow's default branch instead of the right one, even when a later rule would have matched.
2. The headline example from the ticket doesn't work. A weekday after-hours rule (Mon-Fri 18:00-08:00) only covers Tuesday early morning. Calls at 03:00 on Wednesday, Thursday, Friday and Saturday go to the default branch.
3. The API is backwards-incompatible. Creating a rule without time window fields, which was valid before, now returns HTTP 400. Meanwhile updates (POST) and partial updates (PATCH) still accept a zero-length window, which the ticket says must be rejected.

Same-day windows, rules with no window, and forced on/off rules behave exactly as before (AC5). The documentation section is written correctly (AC8), but finding F14 shows that its example doesn't hold on the current code.

## Summary counts

| Metric | Count |
|---|---|
| Partitions | 5 (1 PASS, 4 ISSUES, 0 BLOCKED) |
| Existing tests reused | 1,005 (callflow 859, crossbar 146; includes the 24 tests the branch added) |
| Tests added by QA | 524 in 3 new EUnit modules (254 + 233 + 37) |
| Passed (all EUnit, `make ... test`) | 1,362 (callflow 1,193 of 1,346; crossbar 169 of 183) |
| Failed | 167, all in the QA-added modules (51 + 102 + 14); 0 in existing tests |
| Blocked | 0 |
| Distinct failures | 14 (F1-F14), all 14 confirmed independently by a second model |
| Private harness evaluations (not committed) | About 5.6M (exhaustive sweep and differential vs master) plus a 100k and a 200k random fuzz |

## Partition map

| Partition | Scope | Why | Executor | Tests reused | Tests added | Result | Evidence |
|---|---|---|---|---|---|---|---|
| P1 Existing suites + build | `make -C applications/callflow test`, `crossbar test`, `callflow proper`; `-Werror`; `scripts/code_checks.bash` | DoD; regression for AC5 | Subagent (Claude Opus) | 1,005 | 0 | PASS | callflow `All 859 tests passed.` (48s); crossbar `All 146 tests passed.` (25s; `cb_storage_tests` passed, internet reachable); `proper` with the branch's tests only: `All 859 tests passed.`; master's unmodified `cf_temporal_route_tests` (779) pass against branch code; `-Werror` from `make/kz.mk:50`, applied by `:172` (tests) and `:221` (proper), with no warnings in the build logs; `code_checks.bash` on the 4 changed files: exit 0 |
| P2 Overnight semantics per cycle | New tests for AC1-AC3: date, daily, weekly, monthly, yearly; AC2 and AC3 examples; month, year and leap boundaries; inclusive bounds | The core of the feature | Subagent (Claude Opus) | 0 | 254 (`cf_temporal_route_overnight_qa_tests.erl`) | ISSUES | `Failed: 51. Passed: 203.`; findings F1, F2, F5, F6, F7 |
| P3 Robustness + same-day parity | Crash sweep over 27 rules, 13 windows, every day 2019-2021 and 4 times of day (1.54M evaluations of `is_rule_active/3` and `process_rules/3`); same-day and default windows vs master (1.33M); forced `enabled` (1.18M) | AC4, AC5 | Subagent (Claude Opus) | 0 | 233 (`cf_temporal_route_robustness_qa_tests.erl`) | ISSUES (AC4), PASS (AC5) | 8,640 crashes on branch vs 0 on master, all on day 1; 0 parity mismatches; `Failed: 102. Passed: 131.`; findings F1, F2, F3, F6 |
| P4 API validation | PUT, POST and PATCH through the real `cb_temporal_rules:validate/1,2`, with the `temporal_rules` schema, the fixture DB, `load_merge` and `patch_and_validate` | AC6, AC7 | Subagent (Claude Opus) | 5 (`cb_temporal_rules_tests`) | 37 (`cb_temporal_rules_api_qa_tests.erl`) | ISSUES | `Failed: 14. Passed: 23.`; findings F9-F13 |
| P5 Blast radius + docs | Callers of every changed function; `build_rule`; menu, enable, disable and reset; schema and swagger; running the documented example | AC4, AC5, AC7, AC8 | Subagent (Claude Opus) | 0 | 0 (scratch harnesses in `/tmp`) | ISSUES | Route-level misrouting (F4); yearly crash on the 2nd (F8); doc example false (F14); 200k-case differential with 0 differences for same-day windows |
| Confirmation | Independent fresh-harness reproduction of F1-F14 | Cross-model check requested by the QA lead | Subagent (Claude Sonnet 5; the GPT model rejected the request) | - | - | 14 of 14 CONFIRMED | Harness `/tmp/confirm/confirm_cf.erl`, `confirm_cb.erl` |

## Acceptance-criteria matrix

| AC | Partition | Result | Evidence |
|---|---|---|---|
| AC1 Overnight window opens at start on each rule date and closes at stop on the next day | P2, P3 | **FAIL** | Mid-month daily passes (9 of 9). The window can't be evaluated on the 1st (F1, F2), and weekly windows don't close the next morning after consecutive rule days (F5). |
| AC2 After-midnight part belongs to the opening date for every cycle; weekly Mon-Fri example | P2 | **FAIL** | AC2's own example fails. Sat 03:00 returns `false` (F5, e.g. `Sat 2020-09-19 03:00:00 matches` at `cf_temporal_route_overnight_qa_tests:326`). Monthly and yearly miss the 1st after an end-of-month occurrence (F6, F7). The date cycle passes (15 of 15). |
| AC3 Same across month and year boundaries; daily 22:00-06:00 example | P2, P3 | **FAIL** | Daily `Thu 2020-10-01 02:00:00 matches` crashes (`function_clause`, F1). Jan 1 02:00 crashes (F1). Monthly and yearly Dec 31 to Jan 1 returns `false` (F6, F7). |
| AC4 Never crashes; call reaches a matching branch or default | P3, P5 | **FAIL** | 8,640 crashes on the branch vs 0 on master (F1-F3). A crash sends the call to the `_` default child and skips later matching rules (F4). The yearly `every` ordinal crashes on the 2nd (F8). |
| AC5 Same-day, no-window and `enabled` behavior unchanged; bounds inclusive | P1, P3, P5 | **PASS** | 1.33M boundary evaluations vs master: 0 mismatches. 200k random cases: 0 differences. `enabled` clauses byte-identical to master; 1.18M forced evaluations: 0 failures. 779 master tests pass. 09:00:00 and 17:00:00 active, 08:59:59 and 17:00:01 inactive. |
| AC6 start == stop rejected with 400 on `time_window_stop` for PUT, POST, PATCH | P4 | **FAIL** | PUT is correct (4 of 4 rejected with 400 and `time_window_stop.invalid`). POST (F9) and PATCH (F10) accept start == stop. |
| AC7 Pre-existing payloads still accepted, incl. omitted start and/or stop (defaults 0 and 86400) | P4, P5 | **FAIL** | PUT `{}` window gives 400 `cause: 0` (F11). PUT with only start=0 gives 400 (F12). `core/kazoo_proper/src/pqc_cb_temporal_rules.erl:121-128` creates exactly this payload. |
| AC8 Docs describe overnight windows with an example | P5 | **PASS** (with a caveat) | `applications/crossbar/doc/temporal_rules.md:56-62` adds the section with a Mon-Fri 18:00-08:00 example (64800/28800), matching the ticket spec. The heading level is consistent and the ref doc is in sync. Its example doesn't hold on the current code (F14), and its equal-window and omitted-window claims only hold once F9-F12 are fixed. Those are code defects, not doc defects. |

## Failures

All file:line references are at `81696dbb9f`. Build first with `make -C applications/callflow test` and `make -C applications/crossbar test`. Focused re-run from the app directory:
`KAZOO_CONFIG=/workspace/rel/config-test.ini ERL_LIBS=/workspace/deps:/workspace/core:/workspace/applications /workspace/scripts/eunit_run.escript <module>`

| ID | AC violated | file:line | Repro | Expected | Observed | Suspected cause | Severity |
|---|---|---|---|---|---|---|---|
| F1 | AC1, AC3, AC4 | `applications/callflow/src/module/cf_temporal_route.erl:177-178` then `:543` | `cf_temporal_route_overnight_qa_tests`, test `daily 22:00-06:00: Thu 2020-10-01 02:00:00 matches` (and Jan 1 02:00) | `true` | `error:function_clause` in `calendar:date_to_gregorian_days(2020,9,-1)` | `kz_date:normalize({Y, M, D - 2})` doesn't normalize negative days (`core/kazoo_stdlib/src/kz_date.erl:87-99`), so `{Y,M,-1}` reaches `next_rule_date/2` on day 1 | Critical |
| F2 | AC1, AC2, AC4 | `cf_temporal_route.erl:178` then `:553` | `cf_temporal_route_overnight_qa_tests`, test `weekly Mon-Fri 18:00-08:00 ...: Tue 2020-09-01 03:00:00 matches` (also Mon 2020-06-01 19:00) | `true` | `error:function_clause` (via `calendar:day_of_the_week`) | Same D-2 date as F1, weekly clause | Critical |
| F3 | AC4 | `cf_temporal_route.erl:178` then `:627` / `:754`, then `kz_date.erl:127` | `cf_temporal_route_robustness_qa_tests`, test `monthly every wednesday overnight window on Sep 1 at 03:00:00 returns a boolean` | boolean | `error:function_clause` in `kz_date:find_next_weekday/2` | Same D-2 date as F1, monthly and yearly `every` ordinal clauses | High |
| F4 | AC4 | `cf_temporal_route.erl:126` (`process_rules/3`), `applications/callflow/src/cf_exe.erl:560-566` | Harness (process_rules is not exported under TEST): `process_rules(#temporal{local_date={2020,8,1}, local_sec=12:00}, [DailyOvernight 79200/21600 id "night", Daily 0/86400 id "catch_all"], Call)` | `<<"catch_all">>` (master returns this) | Crash; `cf_exe` logs "action ... died unexpectedly" and `continue(self())` routes to the `_` default child | F1-F3 crash aborts the rule loop, so later matching rules are never evaluated | Critical |
| F5 | AC1, AC2 | `cf_temporal_route.erl:177-182`; weekly `next_rule_date` inclusive at `:580-582`, `find_active_days` at `:928-932` | `cf_temporal_route_overnight_qa_tests`, tests `... Wed 2020-09-16 03:00:00 matches`, `Thu 2020-09-17 03:00:00`, `Fri 2020-09-18 03:00:00`, `Sat 2020-09-19 03:00:00` | `true` | `false` (only Tue 03:00 is `true`) | "Opened yesterday" is computed as `next_rule_date(Rule, D-2) =:= D-1`, but the weekly clause returns D-2 itself when D-2 is a rule day. The fallback `base_time` for weekly searches forward from today. | High |
| F6 | AC2, AC3 | `cf_temporal_route.erl:177-182` | `cf_temporal_route_overnight_qa_tests` group `ac2_monthly_days` / `ac2_monthly_ordinal`, e.g. days=[31] `Tue 2020-09-01 03:00:00 matches`, last Friday `Sat 2020-08-01 03:00:00 matches`; `cf_temporal_route_robustness_qa_tests` `monthly day 31 overnight is active Sep 1 03:00` | `true` | `false` | Same bad D-2 search start: `next_rule_date` from `{Y,M,-1}` lands in the current month, not the previous month's last day | Medium |
| F7 | AC2, AC3 | `cf_temporal_route.erl:177-182` | `cf_temporal_route_overnight_qa_tests` groups `ac2_yearly_date` / `ac2_yearly_ordinal`: yearly Dec 31 and last Thursday of Dec, `Fri 2021-01-01 03:00:00 matches` | `true` | `false` | Same as F6 across the year boundary | Medium |
| F8 | AC4 | `cf_temporal_route.erl:178` then `:754`, then `kz_date:find_next_weekday/2` | Harness: yearly `ordinal = <<"every">>`, month 6, any weekday, overnight 64800/28800, 2016-06-02 03:00 | boolean (master returns `default`) | `error:if_clause` from `calendar:day_of_the_week({2016,6,31})`, for all 7 weekdays | The D-2 lookback (May 31) is combined with the rule's month, producing an invalid date; newly reachable only through the overnight path | Medium |
| F9 | AC6 | `applications/crossbar/src/modules/cb_temporal_rules.erl:183-184` | `cb_temporal_rules_api_qa_tests`, `post_rejects_equal_window` (`:98-107`): 0/0, 28800/28800, 86400/86400, legacy doc + 3600/3600 | `error`, 400, `time_window_stop.invalid` | `success`, no error | `validate_time_window/1` is only called from the PUT clause (`:180-182`); POST uses `load_merge` without it | Medium |
| F10 | AC6 | `cb_temporal_rules.erl:164` then `:152-155`, then `:183-184` | `cb_temporal_rules_api_qa_tests`, `patch_rejects_equal_window` (`:109-129`): both fields equal, and merged-equal (start 61200 vs stored stop 61200; stop 32400 vs stored start 32400) | `error`, 400, `time_window_stop.invalid` | `success` | PATCH goes `patch_and_validate`, then `update/2`, then the same `Id` clause as F9 | Medium |
| F11 | AC7 | `cb_temporal_rules.erl:194-195` | `cb_temporal_rules_api_qa_tests`, `put_accepts_legacy_payloads` (`:156-187`): omit both fields (weekly, yearly holiday, date rule) | `success` | `error`, 400, `{"time_window_stop":{"invalid":{... "cause":0}}}` | `time_window_stop(Doc, 0)` defaults stop to 0; callflow uses 86400 (`cf_temporal_route.hrl:40`). The schema has no default. | High |
| F12 | AC7 | `cb_temporal_rules.erl:194-195` | `cb_temporal_rules_api_qa_tests`, `put_accepts_legacy_payloads`: only `time_window_start: 0` | `success` | `error`, 400, `cause: 0` | Same wrong stop default as F11 | High |
| F13 | AC6 (via ticket defaults) | `cb_temporal_rules.erl:194-195` | `cb_temporal_rules_api_qa_tests`, `put_applies_default_window` (`:189-196`): only start=86400; and PATCH adding start=86400 to a doc with no window | `error`, 400 (effective 86400 == 86400) | `success` | Same wrong stop default; the PATCH case is also F10 | Low |
| F14 | AC2 (documented AC8 example) | `applications/crossbar/doc/temporal_rules.md:60` vs `cf_temporal_route.erl:177-182` | `cf_temporal_route_overnight_qa_tests`, `... Sat 2020-09-05 03:00:00 matches`; harness shows Saturdays 2020-09-05 to 10-03 at 02:00 | `true` ("a call at 02:00 on Saturday matches") | `false` for 59 of 60 consecutive Saturdays; the others crash (F1/F2) | Code defect F5 (plus F1 on the 1st) | Medium |

### Risk ranking

1. **F1, F2, F4 (Critical):** every account with a daily or weekly overnight rule misroutes calls on the 1st of every month, all day, not only overnight. The call also skips any later rule that should match.
2. **F5 and F14 (High):** the headline after-hours use case (Mon-Fri 18:00-08:00) is wrong four mornings out of five. Early calls go to the default branch, which is the exact failure the ticket was meant to prevent.
3. **F11, F12 (High):** API backwards-compatibility break. Existing integrations and `pqc_cb_temporal_rules` that create rules without window fields now get HTTP 400.
4. **F3 (High):** monthly and yearly `every <weekday>` overnight rules crash on day 1.
5. **F6, F7, F8, F9, F10 (Medium):** silent misses at month and year end, a rare yearly crash, and zero-length windows accepted on update.
6. **F13 (Low):** zero-length window reachable only through defaults.

## Blast radius

| Caller / consumer (file:line) | Changed? | Status | Evidence |
|---|---|---|---|
| `cf_temporal_route:handle/2` `:66-67` calling `process_rules/3` | No | At risk | Receives F1-F5 |
| `process_rules/3` clauses for `enabled=false`, `enabled=true`, `cycle = <<>>` (`:80-114`) | No | Cleared | Byte-identical to master; 1.18M forced evaluations with 0 failures |
| `process_rules/3` main clause (`:115-129`) calling `is_rule_active/3` | Yes | Same-day cleared; overnight at risk | 1.33M parity checks with 0 mismatches; F1-F4 |
| `is_rule_active/3` same-day clause (`:141-166`) | Refactor | Cleared | 200k random vs master: 0 differences, 0 new crashes |
| `is_overnight_window_active/3` (`:168-201`) | New | At risk | F1-F8 |
| `base_time/2` (`:208-221`) | Extracted | Cleared for same-day | Logic identical to master's inline code |
| `next_rule_date/2` (`:527+`, callers `:178`, `:219`, `:570`) | No | New call site at risk | `:178` passes an invalid date (F1-F3, F8) and relies on exclusive search (F5) |
| `get_temporal_rules` / `maybe_build_rule` / `build_rule` (`:228-280`) | No | Cleared | Omitted fields give 0/86400; string values coerced; 64800/86400 and 86400/0 evaluate without crashing mid-month |
| `temporal_route_menu`, `enable_*`, `disable_*`, `reset_*` (`:380-500`) | No | Cleared | No window evaluation |
| `cf_util:get_timezone/2`, `load_current_time` | No | Cleared | Unchanged |
| `cf_exe:handle_info/2` `'DOWN'` (`cf_exe.erl:560-566`) | No | Amplifies F1-F3 | An action crash continues to the `_` child (F4) |
| `cb_temporal_rules:on_successful_validation('undefined', _)` (`:180-182`) calling `validate_time_window/1` (`:192`) | Yes | At risk | F11-F13 |
| `cb_temporal_rules:on_successful_validation(Id, _)` (`:183-184`), POST and PATCH | No | Missing validation | F9, F10 |
| `cb_temporal_rules_sets` (`:134-184`) | No | Cleared | Never reads windows |
| `kzd_temporal_rules:time_window_start/2`, `time_window_stop/2` (`core/kazoo_documents/src/kzd_temporal_rules.erl:157,169`) | No | Cleared | Caller-supplied defaults (API uses 0/0, see F11) |
| `kz_attributes:temporal_rules/1` (`core/kazoo_endpoint/src/kz_attributes.erl:44`) | No | Cleared | Reads docs only |
| `core/kazoo_proper/src/pqc_cb_temporal_rules.erl:76-80`, `:121-128` | No | Breaks | Creates a rule with only `name`/`cycle`, so F11 applies |
| Schemas `temporal_rules.json`, `callflows.temporal_route.json`, `swagger.json:40730-40741` | No | Cleared | Unchanged 0-86400; `doc/ref/temporal_rules.md` in sync (`scripts/check-ref-docs.bash` rule) |

## Reused vs added tests

| Module | Kind | Tests | Result |
|---|---|---|---|
| `applications/callflow/test/cf_temporal_route_tests.erl` | Reused (779 master + 19 branch) | 798 | All pass |
| Remaining callflow suite | Reused | 61 | All pass |
| `applications/crossbar/test/cb_temporal_rules_tests.erl` | Reused (branch) | 5 | All pass |
| Remaining crossbar suite | Reused | 141 | All pass |
| `applications/callflow/test/cf_temporal_route_overnight_qa_tests.erl` | **Added** (AC1-AC3) | 254 | 203 pass, 51 fail |
| `applications/callflow/test/cf_temporal_route_robustness_qa_tests.erl` | **Added** (AC4, AC5) | 233 | 131 pass, 102 fail |
| `applications/crossbar/test/cb_temporal_rules_api_qa_tests.erl` | **Added** (AC6, AC7) | 37 | 23 pass, 14 fail |

The added modules compile under the repo's `-Werror` test flags, and `scripts/code_checks.bash` passes on them (exit 0).

### Test design

| Group (module) | AC | Technique / edge | Tests |
|---|---|---|---|
| `fixture_calendar_sanity` (overnight) | - | Re-checks the weekday, ordinal and leap facts the expectations rely on | 19 |
| `ac2_weekly_example` (overnight) | AC2 | All 7 AC2 points on 5 weeks (mid-month, spanning a month, Monday on the 1st twice, spanning a year) with 3 start dates | 77 |
| `ac2_weekly_every_day` (overnight) | AC2 | 03:00 and 19:00 on every weekday | 14 |
| `ac1_daily_midmonth` (overnight) | AC1 | Inside, outside and edges of the window | 9 |
| `ac3_daily_boundaries` (overnight) | AC3 | Month ends of 30 and 31 days, Feb 28/29, Dec 31 to Jan 1 | 15 |
| `ac2_daily_interval` (overnight) | AC2 | Every other day, occurrence vs non-occurrence day | 12 |
| `ac2_date_cycle` (overnight) | AC2, AC3 | Single dates incl. Sep 30 and Dec 31 | 15 |
| `ac2_monthly_days`, `ac2_monthly_ordinal` (overnight) | AC2, AC3 | days 15/30/31; first Monday, last Friday/Monday/Thursday | 45 |
| `ac2_yearly_date`, `ac2_yearly_ordinal` (overnight) | AC2, AC3 | Sep 16; Dec 31 to Jan 1; first Monday of Sep; last Thursday of Dec | 20 |
| `ac1_inclusive_bounds` (overnight) | AC1 | start, start-1, stop next day, stop+1, across month and year ends | 28 |
| `overnight_window_never_crashes` (robustness) | AC4 | `is_boolean` without catching: 15 rule types, 5 dates, 2 times | 150 |
| `overnight_window_never_crashes_on_any_weekday` (robustness) | AC4 | Day 1 on each weekday | 14 |
| `extreme_overnight_windows_never_crash` (robustness) | AC4 | 86399-0, 1-0, 86400-0, 86400-86399 | 12 |
| `overnight_window_on_first_of_month_reaches_rule` (robustness) | AC4 | Expected values on day 1 | 14 |
| `same_day_window_unchanged`, `same_day_window_edges_unchanged`, `default_window_unchanged` (robustness) | AC5 | Values verified against master: boundary seconds, 0-1, 86399-86400, 0-86400 | 43 |
| `put_rejects_equal_window` (api) | AC6 | 0, 28800, 43200, 86400 | 4 |
| `post_rejects_equal_window` (api) | AC6 | 3 values and a legacy doc | 4 |
| `patch_rejects_equal_window` (api) | AC6 | Direct, merged and via defaults | 5 |
| `overnight_windows_accepted` (api) | AC6 | PUT, POST, PATCH | 6 |
| `put_accepts_legacy_payloads`, `put_applies_default_window` (api) | AC7 | Omitted, start-only, stop-only, explicit and documented payloads | 12 |
| `post_and_patch_accept_legacy` (api) | AC7 | Legacy payloads on update | 6 |

## Gaps

- **F4 and F8 have no committed tests.** `process_rules/3` isn't exported under `-ifdef(TEST)`, so route-level behavior (F4) and `enabled` forcing were verified only in private `+export_all` harnesses. The yearly `every` crash on the 2nd (F8) was also reproduced only by harness. Exporting `process_rules/3` under TEST would let a fix PR lock both in.
- **Real HTTP status and envelope:** not exercised. `resp_error_code` 400 plus validation errors were asserted on the context; turning that into an HTTP response happens in `api_resource`/cowboy and needs a running crossbar. The execute phase (`crossbar_doc:save`) needs CouchDB. Schemas load from `priv` in TEST mode, not from `system_schemas`.
- **DST and timezone edges:** out of scope per the ticket; not tested.
- **Monster UI:** out of scope.
- **Ambiguous:** PUT with only `time_window_stop: 0` is rejected (effective 0 == 0). QA treated that as correct per the ticket defaults. Please confirm.
- **Edge cases not tested:** rules with `interval` > 1 for monthly and yearly overnight windows; weekly `interval` > 1 on day 1 is covered only by the crash sweep; `start_date` in the future combined with an overnight window.

## Next action

Ticket moves to **In Progress**. The fix must make the three QA modules pass without weakening them, keep all existing tests green, and address F1-F14. Suggested direction:

- In `is_overnight_window_active/3`, compute "did the rule occur on D-1" with proper day arithmetic, for example `calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Date) - 1)`, and an exclusive or cycle-aware search instead of `kz_date:normalize({Y,M,D-2})`.
- In `cb_temporal_rules`, default stop to 86400 (or skip the check when both fields are absent), and run `validate_time_window/1` on the merged doc for POST and PATCH.
- Consider exporting `process_rules/3` under TEST, with tests for F4 and F8.
