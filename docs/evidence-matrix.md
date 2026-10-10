# Evidence matrix

Fill the **Req. code** column with the exact codes from the hackathon brief (for example F1, F2, D2). The "Proof" column says what to attach. Evidence files come from `scripts/collect-evidence.sh` (folder `docs/test-evidence/<timestamp>/`) and from screenshots in `docs/screenshots/`.

| Req. code | Requirement (in plain words) | Built in | Proof | Status |
|---|---|---|---|---|
| ____ | Live portfolio state from Salesforce data | Day 4 `/portfolio`, dashboard | `live-smoke.txt`; screenshot of dashboard | ☐ |
| ____ | Deterministic decision with explanation | Day 5 engine, `DecisionPanel` | `apex-tests.txt` (engine tests, golden values); screenshot of score breakdown | ☐ |
| ____ | Hard constraints reject unsafe plans | Day 5 constraints | Low-SOC and battery-unavailable tests; screenshot of "Rejected by hard constraints" | ☐ |
| ____ | What-if scenarios | Day 6 `/scenario` | `live-smoke.txt`; screenshot of before/after | ☐ |
| ____ | Agent answers using tools, not guesses | Day 7 actions + agent | `docs/agentforce/agent-test-script.md` results; conversation screenshots | ☐ |
| ____ | Time-based simulation | Day 8 `/simulation` | Same checksum on two runs (`live-smoke.txt`); screenshot of timeline | ☐ |
| ____ | Human approval for risky or low-confidence plans | Day 9 approval service | `e2e-check.txt`; `decisions.txt` showing approver and note; screenshot of approval bar | ☐ |
| ____ | Audit trail | Day 9 `/decisions`, audit panel | `decisions.txt`; screenshot of audit panel | ☐ |
| ____ | Role-based access | Permission sets | `permission-sets.txt`; screenshot of the 403 message for a non-approver | ☐ |
| ____ | Graceful failure and fallback | Day 9 fallback banner | Screenshot of outage switch on, banner visible; `e2e-check.txt` failure-path checks | ☐ |
| ____ | Tests and repeatability | All days | `apex-tests.txt`, `react-tests.txt`, `react-build.txt` | ☐ |

## Screenshot list (save to `docs/screenshots/`)

1. `01-dashboard.png` – portfolio overview.
2. `02-decision-balanced.png` – result with actions and score breakdown.
3. `03-decision-cost-first-pending.png` – approval bar visible.
4. `04-approved-audit.png` – after approval, audit row shows approver and note.
5. `05-non-approver-403.png` – message for a user without the approver set.
6. `06-scenario-cloud-front.png` – before and after.
7. `07-simulation-timeline.png` – eight steps and comparison.
8. `08-fallback-outage.png` – outage switch on, banner and greyed last result.
9. `09-agent-conversation.png` – agent answering with a tool result.

## Honest gaps (keep this list true)

- Agentforce answers are not deterministic; the numbers they quote are, because they come from the engine.
- Data is synthetic. Forecast confidence is a seeded field, not a trained model.
- The simulation is eight 15-minute steps, not a continuous process.
