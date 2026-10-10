# Runbook

Everything needed to stand the project up from nothing, and to recover quickly.

## Prerequisites

Salesforce CLI (`sf`), Node 20 or later, Git, access to the org alias `LWC` (or a free Developer Edition org with Agentforce if yours does not have it).

## Fresh setup

```bash
git clone https://github.com/MuskanGarg365/renewai-orchestrator.git
cd renewai-orchestrator
sf org login web --alias LWC

# 1. Metadata first (objects, fields, custom permission)
sf project deploy start -o LWC \
  --source-dir force-app/main/default/objects \
  --source-dir force-app/main/default/customPermissions
# 2. Apex, then permission sets
sf project deploy start -o LWC --source-dir force-app/main/default/classes
sf project deploy start -o LWC --source-dir force-app/main/default/permissionsets
# 3. Seed data
sf apex run --file scripts/apex/seed.apex -o LWC
# 4. Roles for the demo user
for p in RenewAI_Operator RenewAI_Decision_Access RenewAI_Scenario_Access RenewAI_Agent_Access RenewAI_Audit_Access; do
  sf org assign permset --name $p -o LWC
done
# RenewAI_Approver is assigned only when you want to show approval working.

# 5. App
cd force-app/main/default/uiBundles/renewai
npm install && npm run build && cd ../../../../..
sf project deploy start -o LWC --source-dir force-app/main/default/uiBundles
```

Order matters: fields before classes, classes before permission sets.

## Health checks

```bash
cd force-app/main/default/uiBundles/renewai
node scripts/live-smoke.mjs LWC          # API checks
node scripts/e2e-check.mjs LWC           # full story (needs RenewAI_Approver)
```

## Reset the demo to a clean state

```bash
sf apex run --file scripts/apex/reset-demo.apex -o LWC
```

Deletes decisions, actions and scenarios. It does not touch seed data.

## Known problems and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| 401 in the app | CLI session or token expired | `sf org login web -o LWC`, restart the dev server |
| 403 on decisions | Missing permission set | Assign `RenewAI_Decision_Access` |
| 403 on Approve | User lacks `RenewAI_Approver` (intended) | Assign it, then reload |
| 405 on POST | Apex REST class not deployed | Redeploy classes after fields |
| `MISSING_PRICE` / stale data | Seed data missing for that time | Re-run `seed.apex` |
| Agent cannot run an action | `RenewAI_Agent_Access` not assigned | Assign it |
| Simulation slow | Eight intervals, 32 engine runs | A few seconds is normal |

## Fallback ladder for the demo

1. Live app in the org.
2. Fixture mode: `VITE_DATA_MODE=fixture npm run dev` (needs nothing from Salesforce).
3. Recorded backup video.
