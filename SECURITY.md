# Security

Setlist is a discipline control for cooperating use, not a security boundary. The
[Known limitations](LIMITATIONS.md) list says where it stops, each with a date and a
reason, and a route around a hook that the list already names is a boundary rather than a
vulnerability.

## What to report

- A way to land work on a trunk that the push-time trunk audit, or the forge check on a
  trunk that requires it, should refuse and does not, for a route the Known limitations do
  not name.
- A stamped hook or script that runs, reads or writes something it should not: a command
  built from text an instance controls, a file outside the instance, a secret in a report.
- A hook that fails OPEN (allows everything) on a platform or toolchain where it should
  refuse or report.
- Anything in the published bytes that a user could mistake for a guarantee the code does
  not keep.

## Where

Use GitHub's private vulnerability reporting on this repository (the Security tab, "Report
a vulnerability"), so the report is not public before a fix exists. A refusal you did not
expect, which is not a security problem, has its own public issue form, "A refusal I did not
expect" (`.github/ISSUE_TEMPLATE/refusal.yml`).

Include the platform, the git version, the plugin version, the exact message with its
bracketed code if there was one, and the one command or sequence that shows it.

## What happens

The report is reproduced against the current release. A confirmed hole is either fixed in
the next release, with a case in the suite that fails on the old bytes, or, where fixing it
would move the guarantee somewhere it cannot hold, added to the Known limitations with its
reason. Either way the release notes say what changed, and the reporter is credited unless
they ask not to be.
