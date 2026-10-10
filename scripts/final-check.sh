#!/usr/bin/env bash
# Pre-submission checks. Run from the repository root:  scripts/final-check.sh
set -u
fail=0
say() { printf '%s\n' "$*"; }

say "== 1. Secrets and tokens in tracked files =="
if git grep -nIiE '(refresh[_ -]?token|client[_ -]?secret|sfdx-auth-url|force://|BEGIN (RSA|PRIVATE)|sid=00D|Authorization: *Bearer)' -- . ':!scripts/final-check.sh' ':!scripts/collect-evidence.sh' ':!package-lock.json' ':!**/package-lock.json' ':!**/dist/**' ':!**/build/**' ':!**/node_modules/**' | cut -c1-200 | grep .; then
  say "FOUND possible secrets above. Review each line."; fail=1
else
  say "none found"
fi

say; say "== 2. Auth or env files tracked =="
if git ls-files | grep -E '(^|/)(\.env($|\.)|.*\.key$|.*\.pem$|authFile|.*-auth-url.*)' | grep -v '\.env\.example$'; then
  say "FOUND files that should not be committed."; fail=1
else
  say "none found"
fi

say; say "== 3. Email addresses in seed data, Apex and docs (data must be synthetic) =="
if git grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -- scripts/apex docs force-app/main/default/classes | cut -c1-200 | grep -v -E 'example\.(com|org)|noreply@'; then
  say "Review the addresses above."; fail=1
else
  say "none found"
fi

say; say "== 4. Working tree =="
if [ -n "$(git status --porcelain)" ]; then
  git status --short; say "Uncommitted changes."; fail=1
else
  say "clean"
fi

say; say "== 5. Evidence folders =="
ls -1d docs/test-evidence/*/ 2>/dev/null || { say "no evidence folder yet"; fail=1; }

say
if [ "$fail" -eq 0 ]; then say "ALL CLEAR"; else say "REVIEW NEEDED"; fi
exit "$fail"
