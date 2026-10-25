# system-of-two: a two-repository system for the system spec (spec 0200)

Written for spec 0200 (F1 of the session-zero rebuild), 2026-10-24. It is a small
system of two repositories, an API and a web front end, and a system repository
beside them:

- `IDEA.md` is the one paragraph session zero is given in deep mode, with no code.
- `api/` and `web/` are the two repositories as they would exist before Setlist:
  a few source files each, their tests, their own pipeline file, and the crossings
  between them in plain sight (the front end calls two of the API's endpoints by
  URL; the API calls a payments provider). The retrofit reads them in estate mode.
- `system/system.md` is the shape a system spec takes, with its bootstrap plan.
  The suite's region `system-of-two-0200` (`test/suite/22-system-spec-0200.sh`)
  walks that plan with the real stamp, one repository per step, and asserts that
  both repositories record the same system spec.

Nothing here is executed by the suite: the source files are read, never run, and
no file downloads anything. The cold runs that read this fixture are archived
under `dogfood/` in the private repository.

After the runs (spec 0200, item 4) the documented test command became `node --test tests/*.test.js` in both READMEs, both pipeline files and the plan: the directory form `node --test tests/` that the runs read fails on Node 24.
