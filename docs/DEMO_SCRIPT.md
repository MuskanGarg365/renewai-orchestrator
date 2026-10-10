# Demo script (5 minutes)

Adjust the timings if your slot differs; keep the order. Record a clean take of this as the backup video.

**Before you start:** org open in one window, agent open in another, fixture-mode app (`VITE_DATA_MODE=fixture npm run dev`) ready in a third as the fallback. Run `sf apex run --file scripts/apex/reset-demo.apex -o LWC` so the audit table starts empty. Browser zoom 110%. Notifications off. Keep `RenewAI_Approver` unassigned to the demo user until the approval moment, so the 403 can be shown first (see the rehearsal checklist).

| Time | Show | Say (one idea per line) |
|---|---|---|
| 0:00 | Title / dashboard | "Renewable portfolios change every 15 minutes. Operators have to rebalance power, batteries and the grid, and explain why." |
| 0:20 | Dashboard KPIs, batteries, data-quality banner | "This is live Salesforce data: solar, wind, two batteries, industrial demand, the grid. The banner tells you how fresh and complete the data is." |
| 0:50 | Decision panel, **Balanced**, Run | "The decision is made by a deterministic engine in Apex. Nine candidate plans, hard limits first, then six cost terms. No AI picks a number." |
| 1:20 | Score breakdown, rejected list | "Here is why it won, and here are the plans rejected for breaking a hard limit." |
| 1:40 | **Cost First**, Run | "Different objective, different answer. This one carries higher reliability risk, so it needs a person." |
| 2:00 | Approval bar: click Approve | Without the role: "Only users with the Approver role can do this, and the system says so." Then assign the role, reload, approve with a note. |
| 2:30 | Audit table | "Who approved, when, why, and the correlation ID that ties it to the logs." |
| 2:50 | Scenario panel, **Cloud Front** | "What if a cloud front hits? Same engine, disturbed inputs, before and after side by side." |
| 3:20 | Simulation, Run, timeline | "Two hours, eight steps. The engine decides at every step and the batteries carry over. Totals for cost, carbon, curtailment and reliability events." |
| 3:50 | Objective comparison, checksum | "Same two hours under all four objectives. Run it again and the checksum is identical: it is repeatable." |
| 4:10 | Agentforce | Ask: "Run Cost First and tell me if it needs approval." "The agent calls the same Apex actions and explains the result. It cannot change a setpoint." |
| 4:40 | Outage switch on, Run decision | "If a service fails, the last good result stays visible and is labelled as a fallback. Nothing is re-saved." |
| 4:55 | Architecture slide | "One engine, three doors in, one audit trail." |

## If something goes wrong on stage

- **A call fails or hangs more than 10 seconds:** say "this is the failure path I was going to show", and continue in the fixture-mode window.
- **Agent is slow or off-script:** say "the agent's wording varies, the numbers do not", and read the same numbers from the decision panel.
- **An unexpected 403:** the session lost the permission. Reload the app. Keep the fixture window ready.
