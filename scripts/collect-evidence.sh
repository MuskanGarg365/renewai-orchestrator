#!/usr/bin/env bash
# Collects submission evidence into docs/test-evidence/<stamp>/ .
#   scripts/collect-evidence.sh <org-alias>
# Run from the repository root. Safe to re-run; each run gets its own folder.
set -u
ALIAS="${1:?Usage: scripts/collect-evidence.sh <org-alias>}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="docs/test-evidence/$STAMP"
UI="force-app/main/default/uiBundles/renewai"
mkdir -p "$OUT"

echo "== Apex tests (all RenewAI classes) =="
sf apex run test --target-org "$ALIAS" --wait 20 --result-format human \
  --code-coverage \
  --class-names RenewAIDecisionEngineTest --class-names RenewAIDecisionServiceTest \
  --class-names RenewAIPortfolioServiceTest --class-names RenewAIRestResourceTest \
  --class-names RenewAISmokeTest --class-names RenewAIScenarioCatalogTest \
  --class-names RenewAIScenarioServiceTest --class-names RenewAIAgentActionsTest \
  --class-names RenewAISimulationEngineTest --class-names RenewAISimulationServiceTest \
  --class-names RenewAIApprovalServiceTest --class-names RenewAIApprovalRestTest \
  > "$OUT/apex-tests.txt" 2>&1
echo "apex exit code: $?" | tee -a "$OUT/apex-tests.txt"

echo "== React tests, types, lint, build =="
( cd "$UI" && npm test -- --run ) > "$OUT/react-tests.txt" 2>&1
echo "vitest exit code: $?" | tee -a "$OUT/react-tests.txt"
( cd "$UI" && npx tsc --noEmit -p tsconfig.json && npx eslint src && npm run build ) > "$OUT/react-build.txt" 2>&1
echo "tsc/eslint/build exit code: $?" | tee -a "$OUT/react-build.txt"

echo "== Live end-to-end check =="
( cd "$UI" && node scripts/e2e-check.mjs "$ALIAS" 2026-10-09T06:30:00Z --json "../../../../../$OUT/e2e-timings.json" ) > "$OUT/e2e-check.txt" 2>&1
echo "e2e exit code: $?" | tee -a "$OUT/e2e-check.txt"
( cd "$UI" && node scripts/live-smoke.mjs "$ALIAS" ) > "$OUT/live-smoke.txt" 2>&1
echo "smoke exit code: $?" | tee -a "$OUT/live-smoke.txt"

echo "== Saved records =="
sf data query -o "$ALIAS" -q "SELECT Name, Objective_Mode__c, Approval_Status__c, Approval_Note__c, Decided_By__r.Name, Decided_On__c, Correlation_Id__c FROM Decision__c ORDER BY CreatedDate DESC LIMIT 20" > "$OUT/decisions.txt" 2>&1
sf data query -o "$ALIAS" -q "SELECT Action_Type__c, Quantity_MW__c, Status__c, Decision__r.Name FROM Action__c ORDER BY CreatedDate DESC LIMIT 30" > "$OUT/actions.txt" 2>&1
sf data query -o "$ALIAS" -q "SELECT Name, Scenario_Type__c, Status__c, Correlation_Id__c FROM Scenario__c ORDER BY CreatedDate DESC LIMIT 10" > "$OUT/scenarios.txt" 2>&1

echo "== Org and permission assignments =="
sf org display -o "$ALIAS" --json | python3 -c 'import sys,json;r=json.load(sys.stdin)["result"];print("alias:",r.get("alias"));print("apiVersion:",r.get("apiVersion"));print("instanceUrl:",r.get("instanceUrl"))' > "$OUT/org.txt" 2>&1
sf data query -o "$ALIAS" -q "SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = '$(sf org display -o "$ALIAS" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["username"])')' AND PermissionSet.Name LIKE 'RenewAI%'" > "$OUT/permission-sets.txt" 2>&1

echo
echo "Evidence written to $OUT"
echo "Check for secrets before committing:  grep -rniE 'access ?token|sid=|bearer|refresh ?token' $OUT || echo clean"
