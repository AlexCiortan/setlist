#!/usr/bin/env bash
# private-copy.sh - the one place a private copy of a repository is made. A
# caller that must read a repository without touching it copies it on the
# local disk into a directory it made under mktemp, and reads the copy. Every
# such copy in the plugin and its test suite is made by the function below, so
# a reader finds the one line that makes it and every caller makes it the same
# way. Sourced, never run. forge-check.sh makes its copy in place, because it
# is stamped alone into an instance.
#
# private_copy [git clone options] <source> <destination>
private_copy() {
  git clone "$@"
}
