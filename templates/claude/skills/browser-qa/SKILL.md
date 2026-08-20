---
name: browser-qa
description: QA Pass 1 binding for web UIs (framework Part 5). Playwright driving Chromium against the production build; emits the machine-readable qa-pass-1 verdict block plus the evidence report for the Closing report.
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
6. Print the finished output for pasting into the spec's Closing report, in two
   parts. First the machine-readable verdict block the gates parse (Part 6):

   ```qa-pass-1
   1: PASS
   2: PARTIAL
   ```

   one `<criterion>: PASS|PARTIAL|FAIL` line each, criterion a bare identifier
   with no spaces, and nothing else inside the fence: a non-verdict line there is
   refused rather than skipped. Then the per-criterion report with evidence,
   pasted verbatim below it for the human. A QA pass that is not in the repo did
   not happen.

## Gotchas (field-observed)

- Stale service workers on PWA previews serve the PREVIOUS build. A preview
  that looks unchanged after a deploy is the commonest false FAIL here, and the
  commonest false PASS: a fixed bug can still reproduce, and a broken build can
  still look fine. Hard-reload with the service worker unregistered, or run the
  pass in a fresh context, before believing any result that contradicts the
  diff.
- Write the hollow-check guard about COVERAGE, not selectors. "The selector
  matched" proves the element exists, not that the criterion holds: a card
  reading "Synced just now" off a local count matched every assertion while
  hiding total server-side divergence. State what the check would have to see to
  be WRONG, and check that instead.
