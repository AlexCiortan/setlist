# Contributing

Field reports are the most useful contribution. Every edition so far was distilled from
real projects run end to end, so an issue saying what held and what fought you is a finding
either way. A refusal you did not expect has its own form, "A refusal I did not expect",
which asks for what a reproduction needs.

## Before a pull request

- **Open an issue first.** This repository is exported from the framework's source, where
  the change is made, specced and reviewed. So a pull request here is read as a proposal,
  and it is not merged as it stands.
- **The edition is the protocol.** `setlist.md`, `setlist-operations.md` and
  `setlist-changelog.md` are the one copy of the protocol, and the
  plugin's skills, templates and hooks are bindings of it. A change to one without the other
  is a drift, and it fixes nothing.
- **Run the suite.** `bash test/run-shards.sh` runs it. A change that moves what a hook
  decides comes with a case that fails on the old bytes.
- **Style.** No em-dashes in anything you write: use commas, colons, parentheses or separate
  sentences. Leave out the words `honest`, `honestly`, `honesty`, `genuine`, `genuinely`,
  `load-bearing`, `straightforward`, `straightforwardly` and `quietly`, and keep sentences short: a
  median of 22 words or fewer, with nine in ten at 40 or fewer.

## Security

A problem that should not be public before it is fixed goes through [SECURITY.md](SECURITY.md).

## Licence

Code contributions are under Apache-2.0 and text contributions to the edition's three files
(`setlist.md`, `setlist-operations.md`, `setlist-changelog.md`) under CC BY 4.0, as the
[LICENSE](LICENSE) file says.
