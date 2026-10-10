# Responsible AI and limitations

## Where AI is and is not used

| Task | Done by | Why |
|---|---|---|
| Choosing setpoints (charge, discharge, buy, sell, reserve, curtail) | Deterministic Apex engine | Repeatable, testable, auditable |
| Applying safety limits (SOC, rate, grid, curtailment) | Deterministic constraints | A limit must never be negotiable |
| Explaining a decision in plain language | Engine text; the agent restates it | Explanation is grounded in engine output |
| Understanding a request and choosing a tool | Agentforce agent | Natural language to action |

The agent cannot compute or alter a setpoint. It calls Apex actions and reports what they return.

## Controls

- **Human in the loop.** Plans with confidence below 0.6, or a reliability risk of 0.7 or more, are saved as Pending and their actions as Awaiting Approval. Only the Approver role can release them. Rejection requires a reason.
- **Least privilege.** Separate permission sets for reading, deciding, scenarios, agent actions, approving and audit. Data access runs in user mode.
- **Traceability.** Every response carries a correlation id, saved on the decision. Approver, time and note are stored.
- **Honest failure.** Errors are structured. The UI never presents stale data as current: fallback results are labelled and greyed.
- **Repeatability.** The same input gives the same output; the simulation returns a checksum you can compare.

## Limitations (say these out loud)

- Data is synthetic and seeded. Forecast confidence is a stored field, not a trained model.
- Constants (battery duration, price spread, carbon factor, tolerances) are demo assumptions, not market or grid-code values.
- The engine chooses among nine fixed plan shapes. It is not an optimiser.
- The simulation has eight 15-minute steps and applies disturbances as scripted ramps.
- Agent wording varies between runs. The numbers it quotes do not.
- No real-time control: the system recommends and records; it does not dispatch to equipment.
- Approval is a single role, not a routed workflow.

## Out of scope

Real equipment control, personal data, financial advice, and any use beyond the stated demo.
