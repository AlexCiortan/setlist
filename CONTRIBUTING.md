# Contributing

Field reports are the most useful contribution. Every edition so far was distilled from
real projects run end to end, so an issue saying what held and what fought you is a finding
either way. A refusal you did not expect has its own form, "A refusal I did not expect",
which asks for what a reproduction needs.

## Before a pull request

- **Open an issue first.** This repository is exported from the framework's source, where
  the change is made, specced and reviewed, so a pull request here is read as a proposal
  rather than merged as it stands.
- **The edition is the protocol.** `setlist.md` is the one copy of the protocol, and the
  plugin's skills, templates and hooks are bindings of it; a change to one without the other
  is a drift, not a fix.
- **Run the suite.** `bash test/run-shards.sh` runs it; a change that moves what a hook
  decides comes with a case that fails on the old bytes.
- **Style.** No em-dashes in anything you write: use commas, colons, parentheses or separate
  sentences.

## Security

A problem that should not be public before it is fixed goes through [SECURITY.md](SECURITY.md).

## Licence

Code contributions are under Apache-2.0 and text contributions to `setlist.md` under CC BY
4.0, as the [LICENSE](LICENSE) file says.
