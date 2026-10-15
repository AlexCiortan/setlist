# Security

Setlist is a discipline control for cooperating use, and it is no security boundary. The
[Known limitations](LIMITATIONS.md) list says where it stops, each with a date and a
reason. A route around a hook that the list already names is a boundary, and it is not a
vulnerability.

## What to report

- A way to land work on a trunk that the push-time trunk audit should refuse and does not,
  for a route the Known limitations do not name. The same holds for the forge check on a
  trunk that requires it.
- A stamped hook or script that runs, reads or writes something it should not: a command
  built from text an instance controls, a file outside the instance, a secret in a report.
- A hook that fails OPEN (allows everything) on a platform or toolchain where it should
  refuse or report.
- Anything in the published bytes that a user could mistake for a guarantee the code does
  not keep.

## Where

Use GitHub's private vulnerability reporting on this repository (the Security tab, "Report
a vulnerability"), so the report is not public before a fix exists. A refusal you did not
expect is no security problem. It has its own public issue form, "A refusal I did not
expect" (`.github/ISSUE_TEMPLATE/refusal.yml`).

Include the platform, the git version, the plugin version, the exact message with its
bracketed code if there was one, and the one command or sequence that shows it.

## What happens

The report is reproduced against the current release. A confirmed hole is fixed in the next
release, with a case in the suite that fails on the old bytes. Where a fix would move the
guarantee somewhere it cannot hold, the hole is added to the Known limitations with its
reason instead. Either way the release notes say what changed. The reporter is credited
unless they ask not to be.
