# Defects log

Keep this honest. Reviewers trust a project that shows what broke and how it was fixed.

| # | Found | Symptom | Cause | Fix | Re-test |
|---|---|---|---|---|---|
| D-1 | Day 5 | `POST /decision` returned 405 METHOD_NOT_ALLOWED | Metadata deployed in the wrong order; REST class had no `@HttpPost` in the org | Deploy objects first, then classes and permission set | `live-smoke.txt` |
| D-2 | Day 5 | Deploy error on `Decimal.multiply` | Method not available in Apex | Use the `*` operator | Engine tests |
| D-3 | Day 8 | Governor limit risk in simulation tests | One test method ran many simulations | One run per test method; fresh limits with `Test.startTest()` | Simulation service tests |
| D-4 | Day 9 | Test failed on a leftover mock | `beforeEach` returned the mock function, which Vitest ran as a teardown | Use a block body in `beforeEach` | `react-tests.txt` |
| | | | | | |

Add your own rows as you find them during the Day 9 rehearsal.
