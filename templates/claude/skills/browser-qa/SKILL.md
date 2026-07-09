---
name: browser-qa
description: QA Pass 1 binding for web UIs (framework Part 5). Playwright driving Chromium against the production build; emits the PASS / PARTIAL / FAIL block for the Closing report.
disable-model-invocation: true
---

Run QA Pass 1 for the active spec against the real production build. Reads and
reports; never edits source files and never closes a spec.

0. Preflight the tooling before anything else: Playwright resolves
   (`npx playwright --version`) and its Chromium browser is installed
   (`npx playwright install --dry-run chromium` reports it present, or a
   trivial launch succeeds). If either is missing, STOP and report the exact
   install command (`npm i -D playwright` / `npx playwright install chromium`)
   as a finding; never install software yourself. A QA run on missing tooling
   produces false PARTIALs, which are worse than a delayed run.
1. Build and serve the PRODUCTION bundle. Never test the dev server: build-only
   issues (service workers, asset paths) hide behind it.
2. Write a throwaway per-spec driver script from the spec's acceptance criteria,
   taken verbatim. Run it at the spec's declared viewports.
3. One fresh browser context per scenario: a fresh context is a true first-run
   profile with its own empty storage. Never rely on clearing storage by hand.
4. Screenshot key states and actually look at the screenshots. A blank or broken
   frame is a FAIL even when the DOM assertions pass; compare against the spec's
   redline or mock when one is bound.
5. Emit one PASS / PARTIAL / FAIL line per criterion with one line of evidence.
   Honest PARTIALs: anything headless cannot exercise (disabled storage, native
   file dialogs) is a PARTIAL with the reason, leaning on unit coverage, never a
   claimed PASS.
6. Print the finished block for pasting into the spec's Closing report. A QA
   pass that is not in the repo did not happen.
