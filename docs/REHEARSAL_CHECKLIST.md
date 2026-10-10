# Rehearsal checklist

Tick each line during a full cold run. Do it twice: once alone, once in front of one person.

## Environment
- [ ] Org login valid (`sf org display -o LWC`)
- [ ] `scripts/apex/reset-demo.apex` run, audit table empty
- [ ] Seed data present (12 assets, 96 intervals)
- [ ] Latest bundle deployed; app opens from the org
- [ ] Fixture-mode window open as the fallback
- [ ] Backup video opens and plays with sound
- [ ] Notifications off, browser zoom set, tabs closed

## Roles
- [ ] Demo user has Operator, Decision, Scenario, Agent and Audit sets
- [ ] `RenewAI_Approver` can be assigned live (or a second user holds it)
- [ ] A non-approver sees the clear 403 message
- [ ] After assigning the approver set, approval succeeds (reload the app first)

## Path
- [ ] Dashboard loads with the data-quality banner
- [ ] Balanced decision: actions, score breakdown, rejected list
- [ ] Cost First is Pending; approval bar visible
- [ ] Approve with a note; audit row shows approver and note
- [ ] Cloud Front scenario shows before and after
- [ ] Simulation: eight rows, KPI cards, comparison table
- [ ] Second simulation run has the same checksum
- [ ] Agent answers the Cost First question and says it needs approval
- [ ] Outage switch: fallback badge and greyed result appear, then recover

## Timing and delivery
- [ ] Whole demo fits the slot with 20 seconds spare
- [ ] Every sentence can be said in plain words
- [ ] An answer ready for each question below

## Questions to be ready for
1. *Where is the AI?* In conversation and explanation. Numbers come from the deterministic engine.
2. *Why not let the AI decide?* Repeatability, auditability and hard limits. Any decision can be replayed.
3. *What stops a bad plan?* Hard constraints reject it before scoring; low confidence or high reliability risk requires a human.
4. *Who can approve?* Only users with the Approver permission set; others get a 403.
5. *What if Salesforce or the agent fails?* Structured errors with correlation ids; the app shows the last good result as a labelled fallback.
6. *Is the data real?* Synthetic, seeded for the demo, shaped like a real feed.
7. *What next?* Real forecasts, more assets, scheduled runs, approval routing.

## Issues found
Write them in `docs/defects-log.md`.
