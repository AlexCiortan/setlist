# Shard 20: Windows (spec 0179). Sourced by test/run-tests.sh.
#
# =============================================================================
# JQ'S LINE ENDING, CARRIED ON EVERY PLATFORM (spec 0179, cause C).
#
# A native jq on Windows ends every line in CRLF, and Git Bash drops a CR only
# at the very end of a command substitution, so every line of a jq list but the
# last kept one: a role read as "src\r", matched no path, and the scope hook and
# the trunk audit failed OPEN (measured on the probe machine at the spec's cut).
# The fix is one probe line, byte-identical in every shipped jq reader, that
# finds a jq ending lines in CR and reads it through its own -b (jq 1.7 and
# later writes LF with it).
#
# The fixture jq here models Windows' jq on ANY platform: it writes CRLF unless
# it is given -b, so the Linux and macOS legs carry the Windows defect's guard
# without a Windows runner. A second fixture also refuses -b, which is Windows'
# jq 1.6: the hooks must then refuse by name as a broken jq, never read CR.
# =============================================================================
# >>> SHARD-BEGIN jq-crlf-0179 smoke=crlf cost=2
if shard_region jq-crlf-0179; then

JCR="$WORK/jq-crlf-0179"
rm -rf "$JCR"; mkdir -p "$JCR/bin-crlf" "$JCR/bin-old"
JCR_REAL="$(command -v jq)"
# Wrapper scripts, never links (the harness rule since spec 0168: Windows cannot
# run a linked or copied MSYS executable).
cat > "$JCR/bin-crlf/jq" <<JCREOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in -b|--binary) exec "$JCR_REAL" "\$@" ;; esac; done
set -o pipefail
"$JCR_REAL" "\$@" | awk '{ printf "%s\r\n", \$0 }'
JCREOF
cat > "$JCR/bin-old/jq" <<JCREOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in -b|--binary) echo "jq: Unknown arguments: \$a" >&2; exit 2 ;; esac; done
set -o pipefail
"$JCR_REAL" "\$@" | awk '{ printf "%s\r\n", \$0 }'
JCREOF
chmod +x "$JCR/bin-crlf/jq" "$JCR/bin-old/jq"

# The fixture's own precondition, asserted so it can never pass vacuously: it
# writes CR without -b and none with it.
JCR_PRE="$(printf '["x","y"]' | PATH="$JCR/bin-crlf:$PATH" jq -r '.[]' | od -c | tr -d ' \n')"
JCR_PREB="$(printf '["x","y"]' | PATH="$JCR/bin-crlf:$PATH" jq -b -r '.[]' | od -c | tr -d ' \n')"
if [[ "$JCR_PRE" == *'\r'* && "$JCR_PREB" != *'\r'* ]]; then
  ok "jq crlf precondition: the fixture jq writes CRLF, and LF under -b, as a native jq on Windows does"
else
  bad "jq crlf precondition: the fixture jq writes CRLF, and LF under -b, as a native jq on Windows does" "without -b: $JCR_PRE; with -b: $JCR_PREB"
fi

# A scaffolded instance with TWO role paths, the shape that fails open: the first
# role is a line of a list, so it is the one that kept its CR.
JCR_P="$JCR/proj"
mkdir -p "$JCR_P/src" "$JCR_P/docs" "$JCR_P/.claude"
git -C "$JCR_P" init -q
git -C "$JCR_P" config user.email t@example.invalid
git -C "$JCR_P" config user.name T
git -C "$JCR_P" config commit.gpgsign false
printf 'x\n' > "$JCR_P/README.md"
git -C "$JCR_P" add -A >/dev/null; git -C "$JCR_P" commit -qm base >/dev/null; git -C "$JCR_P" branch -M main
printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$JCR_P/.claude/sdd.json"
git -C "$JCR_P" add -A >/dev/null; git -C "$JCR_P" commit -qm adopt >/dev/null
jcr_scope() { # jcr_scope <bin dir> <file_path> -> the hook's verdict or its code
  local out
  out="$(jq -nc --arg f "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}' \
         | (cd "$JCR_P" && PATH="$1:$PATH" CLAUDE_PROJECT_DIR="$JCR_P" bash "$HOOKS/scope-hook.sh" 2>/dev/null))"
  [[ -n "$out" ]] || { printf silent; return 0; }
  printf '%s' "$(printf '%s' "$out" | jq -r '.setlistAdvisory.code // .setlistAdvisory.verdict // "silent"' 2>/dev/null | tr -d '\r')"
}
JCR_GOT="$(jcr_scope "$JCR/bin-crlf" "$JCR_P/src/a.txt")"
if [[ "$JCR_GOT" == "SH-TRUNK-WRITE" ]]; then
  ok "jq crlf a: under a jq that writes CRLF the scope hook still names a role write on the trunk"
else
  bad "jq crlf a: under a jq that writes CRLF the scope hook still names a role write on the trunk" "got $JCR_GOT"
fi
JCR_GOT="$(jcr_scope "$JCR/bin-crlf" "$JCR_P/docs/a.md")"
if [[ "$JCR_GOT" == "silent" ]]; then
  ok "jq crlf b (control): under the same jq a docs write on the trunk draws nothing"
else
  bad "jq crlf b (control): under the same jq a docs write on the trunk draws nothing" "got $JCR_GOT"
fi
JCR_GOT="$(jcr_scope "$JCR/bin-old" "$JCR_P/src/a.txt")"
if [[ "$JCR_GOT" == "SH-JQ-BROKEN" ]]; then
  ok "jq crlf c: a jq that writes CRLF and refuses -b is reported as broken by name, never read"
else
  bad "jq crlf c: a jq that writes CRLF and refuses -b is reported as broken by name, never read" "got $JCR_GOT"
fi

# The trunk audit (and, through the lockstep, the library's reader): a role-code
# commit straight onto the trunk after adoption is a violation.
printf 'code\n' > "$JCR_P/src/a.txt"
git -C "$JCR_P" add -A >/dev/null; git -C "$JCR_P" -c core.hooksPath=/dev/null commit -qm 'feature code, no spec' >/dev/null
JCR_OUT="$(cd "$JCR_P" && PATH="$JCR/bin-crlf:$PATH" bash "$ROOT/scripts/trunk-audit.sh" 2>&1)"; JCR_RC=$?
if [[ "$JCR_RC" -eq 1 && "$JCR_OUT" == *VIOLATION* && "$JCR_OUT" != *'src?'* ]]; then
  ok "jq crlf d: under a jq that writes CRLF the trunk audit reads the role src and reports the role-code commit"
else
  bad "jq crlf d: under a jq that writes CRLF the trunk audit reads the role src and reports the role-code commit" "rc=$JCR_RC $(printf '%s' "$JCR_OUT" | tr '\n' ' ' | cut -c1-200)"
fi
JCR_OUT="$(cd "$JCR_P" && PATH="$JCR/bin-old:$PATH" bash "$ROOT/scripts/trunk-audit.sh" 2>&1)"; JCR_RC=$?
if [[ "$JCR_RC" -eq 2 && "$JCR_OUT" == *SLH-JQ-BROKEN* ]]; then
  ok "jq crlf e: the trunk audit refuses a jq that writes CRLF and refuses -b as broken, by name"
else
  bad "jq crlf e: the trunk audit refuses a jq that writes CRLF and refuses -b as broken, by name" "rc=$JCR_RC $(printf '%s' "$JCR_OUT" | tr '\n' ' ' | cut -c1-200)"
fi
JCR_ROLES="$( (PATH="$JCR/bin-crlf:$PATH"; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_role_paths "$JCR_P") 2>/dev/null | od -c | tr -d ' \n')"
if [[ -n "$JCR_ROLES" && "$JCR_ROLES" != *'\r'* ]]; then
  ok "jq crlf f: the hook library reads the role list with no CR under a jq that writes CRLF"
else
  bad "jq crlf f: the hook library reads the role list with no CR under a jq that writes CRLF" "read: $JCR_ROLES"
fi

# ONE LINE, BYTE-IDENTICAL, in every shipped reader that runs jq before sourcing
# the library (the forge check sources it first and inherits its definition).
JCR_LINE="case \"\$(printf '[\"x\",\"y\"]' | command jq -r '.[]' 2>/dev/null)\" in *\$'\\r'*) jq() { command jq -b \"\$@\"; } ;; esac"
JCR_MISS=""
for f in templates/git-hooks/setlist-hook-lib.sh templates/hooks/scope-hook.sh templates/hooks/bypass-deny.sh \
         templates/hooks/regrounding-hook.sh templates/hooks/stop-hook.sh scripts/trunk-audit.sh \
         scripts/refresh-instance.sh scripts/stamp.sh; do
  [[ "$(grep -cxF -- "$JCR_LINE" "$ROOT/$f")" == "1" ]] || JCR_MISS="$JCR_MISS $f"
done
if [[ -z "$JCR_MISS" ]] && grep -q 'setlist-hook-lib.sh' "$ROOT/scripts/forge-check.sh"; then
  ok "jq crlf g: the line-ending probe is one byte-identical line in all eight readers, and the forge check sources the library"
else
  bad "jq crlf g: the line-ending probe is one byte-identical line in all eight readers, and the forge check sources the library" "missing or not once in:$JCR_MISS"
fi

fi; shard_region_end
# <<< SHARD-END jq-crlf-0179


# =============================================================================
# THE WINDOWS SPELLINGS OF A PATH, ONE NORMALISER (spec 0179, cause N; the
# intake's J1). Claude Code on Windows sends file_path as C:\...; git answers
# --git-common-dir as C:/...; a recorded core.hooksPath can be either. Each
# reader tested for a leading / and read those as relative. slh_path_norm is
# byte-identical in the scope hook and the hook library; the corpus reads it on
# every platform with OSTYPE set in-process (bash's own variable, so the
# function's platform is the caller's), and the hooks themselves are driven
# under the real spellings wherever this suite runs under MSYS or Cygwin.
# Windows paths are built with cygpath, never typed through a heredoc.
# =============================================================================
# >>> SHARD-BEGIN path-norm-0179 smoke=path cost=2
if shard_region path-norm-0179; then

PN_S="$(awk '/^slh_path_norm\(\)/{p=1} p{print} /^slh_path_abs\(\)/{exit}' "$HOOKS/scope-hook.sh")"
PN_L="$(awk '/^slh_path_norm\(\)/{p=1} p{print} /^slh_path_abs\(\)/{exit}' "$ROOT/templates/git-hooks/setlist-hook-lib.sh")"
if [[ -n "$PN_S" && "$PN_S" == "$PN_L" ]]; then
  ok "path norm a: slh_path_norm and slh_path_abs are byte-identical in the scope hook and the hook library"
else
  bad "path norm a: slh_path_norm and slh_path_abs are byte-identical in the scope hook and the hook library" "scope hook $(printf '%s' "$PN_S" | grep -c '') lines, library $(printf '%s' "$PN_L" | grep -c '') lines"
fi
# The corpus: <OSTYPE> <input> <expected>. A backslash is built with printf and so
# reaches the function as one backslash; no Windows path is typed through a heredoc.
PN_BAD=""
pn_row() { # pn_row <ostype> <input> <expected>
  local got
  got="$( eval "$PN_S"; OSTYPE="$1"; slh_path_norm "$2"; printf '%s' "$SLH_PATH_NORMED" )"
  [[ "$got" == "$3" ]] || PN_BAD="$PN_BAD [$1 '$2' -> '$got', wanted '$3']"
}
pn_abs() { # pn_abs <ostype> <input> <yes|no>
  local got
  got="$( eval "$PN_S"; OSTYPE="$1"; if slh_path_abs "$2"; then printf yes; else printf no; fi )"
  [[ "$got" == "$3" ]] || PN_BAD="$PN_BAD [$1 abs '$2' -> $got, wanted $3]"
}
PN_BS="$(printf '\\')"
for pn_os in cygwin msys; do
  pn_row "$pn_os" "C:${PN_BS}Users${PN_BS}a b${PN_BS}src${PN_BS}x.txt" "C:/Users/a b/src/x.txt"
  pn_row "$pn_os" "C:/Users/x" "C:/Users/x"
  pn_row "$pn_os" "c:/x" "c:/x"
  pn_row "$pn_os" "D:${PN_BS}" "D:/"
  pn_row "$pn_os" "C:" "C:/"
  pn_row "$pn_os" "/c/x" "c:/x"
  pn_row "$pn_os" "/c" "c:/"
  pn_row "$pn_os" "/tmp/p/src/a.txt" "/tmp/p/src/a.txt"
  pn_row "$pn_os" "src/a.txt" "src/a.txt"
  pn_row "$pn_os" "src${PN_BS}a.txt" "src${PN_BS}a.txt"
  pn_row "$pn_os" "C:x" "C:x"
  pn_row "$pn_os" "" ""
  pn_abs "$pn_os" "C:/x" yes; pn_abs "$pn_os" "/x" yes; pn_abs "$pn_os" "x" no; pn_abs "$pn_os" "C:x" no
done
for pn_os in darwin24 linux-gnu; do
  pn_row "$pn_os" "C:${PN_BS}Users${PN_BS}x" "C:${PN_BS}Users${PN_BS}x"
  pn_row "$pn_os" "C:/Users/x" "C:/Users/x"
  pn_row "$pn_os" "/c/x" "/c/x"
  pn_row "$pn_os" "src${PN_BS}a.txt" "src${PN_BS}a.txt"
  pn_abs "$pn_os" "C:/x" no; pn_abs "$pn_os" "/x" yes
done
if [[ -z "$PN_BAD" ]]; then
  ok "path norm b: the corpus, 44 rows: C:\\, C:/, /c/ and a bare drive read as git's C:/ spelling and as absolute under MSYS and Cygwin; every other path, and every path elsewhere, unchanged and relative as before"
else
  bad "path norm b: the corpus: C:\\, C:/, /c/ and a bare drive read as git's C:/ spelling and as absolute under MSYS and Cygwin; every other path, and every path elsewhere, unchanged and relative as before" "$PN_BAD"
fi

case "${OSTYPE:-}" in
  msys*|cygwin*)
    PN_P="$WORK/path-norm-0179"
    rm -rf "$PN_P"; mkdir -p "$PN_P/src" "$PN_P/docs" "$PN_P/.claude" "$PN_P/.chained"
    git -C "$PN_P" init -q
    git -C "$PN_P" config user.email t@example.invalid
    git -C "$PN_P" config user.name T
    git -C "$PN_P" config commit.gpgsign false
    printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$PN_P/.claude/sdd.json"
    printf 'x\n' > "$PN_P/src/a.txt"
    git -C "$PN_P" add -A >/dev/null; git -C "$PN_P" commit -qm seed >/dev/null; git -C "$PN_P" branch -M main
    PN_W="$(cygpath -w "$PN_P")"; PN_M="$(cygpath -m "$PN_P")"
    PN_D="$(printf '%s' "${PN_M:0:1}" | tr '[:upper:]' '[:lower:]')"; PN_U="/$PN_D${PN_M:2}"
    pn_scope() { # pn_scope <file_path> -> deny | allow
      local out
      out="$(jq -nc --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}' \
             | (cd "$PN_P" && CLAUDE_PROJECT_DIR="$PN_W" bash "$HOOKS/scope-hook.sh" 2>/dev/null))"
      if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // empty' 2>/dev/null)" == "deny" ]]; then printf deny; else printf allow; fi
    }
    pn_case() { # pn_case <label> <want> <got>
      if [[ "$3" == "$2" ]]; then ok "path norm $1: $2"; else bad "path norm $1: wanted $2" "got $3"; fi
    }
    pn_case "c, a role write spelled C:\\ on the trunk" deny "$(pn_scope "$PN_W${PN_BS}src${PN_BS}new.txt")"
    pn_case "c2 (control), a docs write spelled C:\\" allow "$(pn_scope "$PN_W${PN_BS}docs${PN_BS}x.md")"
    pn_case "d, a role write spelled C:/ on the trunk" deny "$(pn_scope "$PN_M/src/new.txt")"
    pn_case "d2 (control), a docs write spelled C:/" allow "$(pn_scope "$PN_M/docs/x.md")"
    pn_case "e, a role write spelled /c/ on the trunk" deny "$(pn_scope "$PN_U/src/new.txt")"
    pn_case "e2 (control), a docs write spelled /c/" allow "$(pn_scope "$PN_U/docs/x.md")"
    # The root as the MSYS mount spells it (/tmp/... for the user's Temp) and the write as
    # Claude Code does (C:\...): the shape a /c/ normaliser missed on the probe machine.
    PN_OUT="$(jq -nc --arg f "$PN_W${PN_BS}src${PN_BS}g.txt" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}' \
      | (cd "$PN_P" && CLAUDE_PROJECT_DIR="$PN_P" bash "$HOOKS/scope-hook.sh" 2>/dev/null) | jq -r '.setlistAdvisory.verdict // empty' 2>/dev/null)"
    pn_case "g, the root spelled as MSYS mounts it and a role write spelled C:\\" deny "${PN_OUT:-allow}"
    # The chain runner: a hooks_chain recorded in git's C:/ spelling runs its hook.
    printf '#!/usr/bin/env bash\necho chained-ran\n' > "$PN_P/.chained/pre-commit"; chmod +x "$PN_P/.chained/pre-commit"
    jq --arg c "$PN_M/.chained" '.hooks_chain = $c' "$PN_P/.claude/sdd.json" > "$PN_P/.claude/sdd.json.t" && mv "$PN_P/.claude/sdd.json.t" "$PN_P/.claude/sdd.json"
    PN_OUT="$( (. "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_chain_displaced "$PN_P" pre-commit 0) 2>&1 )"
    if [[ "$PN_OUT" == *chained-ran* && "$PN_OUT" != *SLH-CHAIN-UNREACHABLE* ]]; then
      ok "path norm f: a hooks_chain recorded as C:/... runs the chained hook"
    else
      bad "path norm f: a hooks_chain recorded as C:/... runs the chained hook" "$(printf '%s' "$PN_OUT" | tr '\n' ' ' | cut -c1-200)"
    fi
    ;;
  *) printf 'SKIPPED  path norm c to f: the Windows spellings are driven only under MSYS or Cygwin (OSTYPE=%s)\n' "${OSTYPE:-unset}" ;;
esac

fi; shard_region_end
# <<< SHARD-END path-norm-0179


# =============================================================================
# A RETROFIT'S ROLE PATHS ARE READ FROM THE TREE, NEVER DEFAULTED (spec 0179,
# field item (d), the owner's finding of 2026-09-29). The answers defaulted to
# src and tests and the stamp created both directories in every mode, so a
# retrofit that kept the defaults on a project laid out otherwise (the field
# record's shape: the code in app/, the tests in spec/) stamped an empty src/ and
# tests/ and governed none of the real code while reading armed.
# =============================================================================
# >>> SHARD-BEGIN retrofit-roles-0179 cost=2
if shard_region retrofit-roles-0179; then

RR="$WORK/retrofit-roles-0179"
rr_repo() { # rr_repo <dir>: the field shape, committed
  rm -rf "$1"; mkdir -p "$1/app/core" "$1/spec"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name T
  git -C "$1" config commit.gpgsign false
  printf 'x = 1\n' > "$1/app/main.py"; printf 'y = 2\n' > "$1/app/util.py"; printf 'z = 3\n' > "$1/app/core/model.py"
  printf 'def test(): pass\n' > "$1/spec/test_main.py"
  printf '# P\n' > "$1/README.md"; printf 'echo hi\n' > "$1/build.sh"
  git -C "$1" add -A >/dev/null; git -C "$1" commit -qm seed >/dev/null; git -C "$1" branch -M main
}
RR_ANS="$WORK/retrofit-roles-0179.ans"
printf 'project_name=P\nstack=Python\nworking_mode=solo\nui=no\nopusplan_verified=yes\ndesign_surface=no\nmode=retrofit\n' > "$RR_ANS"

rr_repo "$RR/a"
RR_OUT="$(bash "$ROOT/scripts/stamp.sh" "$RR_ANS" "$RR/a" 2>&1)"; RR_RC=$?
if [[ "$RR_RC" -eq 1 && "$RR_OUT" == *'src_role is "src", which does not exist in this repository'* \
      && "$RR_OUT" == *"inventory scan"* && "$RR_OUT" == *"takes a list"* \
      && ! -e "$RR/a/src" && ! -e "$RR/a/tests" && ! -e "$RR/a/.claude" ]]; then
  ok "retrofit roles a: a retrofit whose answers kept the default src on a project with its code in app/ is refused by name, nothing written"
else
  bad "retrofit roles a: a retrofit whose answers kept the default src on a project with its code in app/ is refused by name, nothing written" \
      "rc=$RR_RC src/:$([[ -e "$RR/a/src" ]] && echo created || echo absent) .claude/:$([[ -e "$RR/a/.claude" ]] && echo written || echo absent) $(printf '%s' "$RR_OUT" | tail -n 3 | tr '\n' ' ' | cut -c1-200)"
fi

rr_repo "$RR/b"
{ cat "$RR_ANS"; printf 'src_role=app\ntests_role=spec\n'; } > "$RR_ANS.b"
RR_OUT="$(bash "$ROOT/scripts/stamp.sh" "$RR_ANS.b" "$RR/b" 2>&1)"; RR_RC=$?
if [[ "$RR_RC" -eq 0 && ! -e "$RR/b/src" && ! -e "$RR/b/tests" \
      && "$(jq -r '.roles.src + " " + .roles.tests' "$RR/b/.claude/sdd.json" 2>/dev/null)" == "app spec" ]]; then
  ok "retrofit roles b (control): the scan's paths stamp, and no src/ or tests/ is created"
else
  bad "retrofit roles b (control): the scan's paths stamp, and no src/ or tests/ is created" "rc=$RR_RC $(printf '%s' "$RR_OUT" | tail -n 2 | tr '\n' ' ' | cut -c1-200)"
fi

# The skill's scan, extracted from the fenced block after its sentence and run.
RR_SCAN="$(awk '/the inventory scan from the repository root/ { s = 1 } s && /^```sh$/ { f = 1; next } f && /^```$/ { exit } f { print }' "$ROOT/skills/retrofit/SKILL.md")"
RR_READ="$( cd "$RR/b" && eval "$RR_SCAN" 2>&1 )"
if [[ -n "$RR_SCAN" && "$(printf '%s\n' "$RR_READ" | head -n 1)" == "3 app" && "$RR_READ" == *"1 spec (tests)"* && "$RR_READ" != *" src"* ]]; then
  ok "retrofit roles c: the retrofit skill's inventory scan ranks app first and marks spec as the tests candidate"
else
  bad "retrofit roles c: the retrofit skill's inventory scan ranks app first and marks spec as the tests candidate" "scan: $(printf '%s' "$RR_SCAN" | cut -c1-60); read: $(printf '%s' "$RR_READ" | tr '\n' '|')"
fi
RR_SKILL_AWK="$(printf '%s' "$RR_SCAN" | sed -e "s/^git ls-files | awk -F\/ '//" -e "s/' | sort -rn\$//")"
RR_REFRESH_AWK="$(grep "^ROLE_SCAN_AWK='" "$ROOT/scripts/refresh-instance.sh" | sed -e "s/^ROLE_SCAN_AWK='//" -e "s/'\$//")"
if [[ -n "$RR_SKILL_AWK" && "$RR_SKILL_AWK" == "$RR_REFRESH_AWK" ]]; then
  ok "retrofit roles d: the skill's scan and the refresh's are one awk program, byte for byte"
else
  bad "retrofit roles d: the skill's scan and the refresh's are one awk program, byte for byte" "skill $(printf '%s' "$RR_SKILL_AWK" | cut -c1-60); refresh $(printf '%s' "$RR_REFRESH_AWK" | cut -c1-60)"
fi

# The refresh names a role path that holds nothing, with the candidates beside it.
jq '.roles = {"src": "src", "tests": "tests"}' "$RR/b/.claude/sdd.json" > "$RR/b/.claude/sdd.json.t" && mv "$RR/b/.claude/sdd.json.t" "$RR/b/.claude/sdd.json"
RR_OUT="$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/scripts/refresh-instance.sh" "$RR/b" 2>&1)"
if [[ "$RR_OUT" == *'the role path "src" (does not exist) "tests" (does not exist), so no layer judges any code by it'* && "$RR_OUT" == *"3 source files in app"* ]]; then
  ok "retrofit roles e: the refresh's report names a role path the repository does not have, with the scan's candidates"
else
  bad "retrofit roles e: the refresh's report names a role path the repository does not have, with the scan's candidates" "$(printf '%s' "$RR_OUT" | grep -i 'role' | head -n 2 | cut -c1-240)"
fi
mkdir -p "$RR/b/src"; : > "$RR/b/src/.keep"
jq '.roles = {"src": ["app", "src"], "tests": "spec"}' "$RR/b/.claude/sdd.json" > "$RR/b/.claude/sdd.json.t" && mv "$RR/b/.claude/sdd.json.t" "$RR/b/.claude/sdd.json"
RR_OUT="$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/scripts/refresh-instance.sh" "$RR/b" 2>&1)"
if [[ "$RR_OUT" == *'the role path "src" (holds no tracked file), so no layer'* && "$RR_OUT" != *'"app"'* && "$RR_OUT" != *'"spec"'* ]]; then
  ok "retrofit roles f: a listed role that exists but holds no tracked file is named; the roles that hold code are not"
else
  bad "retrofit roles f: a listed role that exists but holds no tracked file is named; the roles that hold code are not" "$(printf '%s' "$RR_OUT" | grep -i 'role' | head -n 2 | cut -c1-240)"
fi

fi; shard_region_end
# <<< SHARD-END retrofit-roles-0179


# =============================================================================
# THE GATE VERIFICATION CHECKS FOR jq FIRST (spec 0179, field item (b)). Git for
# Windows ships no jq; the stamped /scaffold skill verified the gate command with
# ( eval "$(jq -r .gate_command .claude/sdd.json)" ), which with no jq evals an
# empty string and prints 0: a false pass. The line is extracted from the
# template and from the retrofit skill and run as the model would run it.
# =============================================================================
# >>> SHARD-BEGIN gate-verify-0179 cost=1
if shard_region gate-verify-0179; then

GV="$WORK/gate-verify-0179"
rm -rf "$GV"; mkdir -p "$GV/.claude" "$GV/nojq"
gv_line() { grep -m 1 'eval "$(jq -r .gate_command .claude/sdd.json)"' "$1" | sed 's/^ *//'; }
gv_run() { # gv_run <line> <gate command> <PATH> -> what the line prints
  jq -n --arg g "$2" '{gate_command: $g}' > "$GV/.claude/sdd.json"
  ( cd "$GV" && PATH="$3" && eval "$1" ) 2>&1
}
GV_BAD=""
for gv_f in "$ROOT/templates/claude/skills/scaffold/SKILL.md.tmpl" "$ROOT/skills/retrofit/SKILL.md"; do
  gv_l="$(gv_line "$gv_f")"
  [[ -n "$gv_l" ]] || { GV_BAD="$GV_BAD [${gv_f#"$ROOT"/}: no verification line]"; continue; }
  gv_o="$(gv_run "$gv_l" "false" "$GV/nojq")"
  [[ "$gv_o" == *"jq is not installed"* && "$gv_o" != "0" ]] || GV_BAD="$GV_BAD [${gv_f#"$ROOT"/} with no jq printed: $gv_o]"
  gv_o="$(gv_run "$gv_l" "false" "$PATH")"; [[ "$gv_o" == "1" ]] || GV_BAD="$GV_BAD [${gv_f#"$ROOT"/} gate false printed: $gv_o]"
  gv_o="$(gv_run "$gv_l" "true" "$PATH")"; [[ "$gv_o" == "0" ]] || GV_BAD="$GV_BAD [${gv_f#"$ROOT"/} gate true printed: $gv_o]"
done
if [[ -z "$GV_BAD" ]]; then
  ok "gate verify a: with no jq the verification says jq is missing instead of printing 0; with jq it prints the gate's status (the template and the retrofit skill)"
else
  bad "gate verify a: with no jq the verification says jq is missing instead of printing 0; with jq it prints the gate's status (the template and the retrofit skill)" "$GV_BAD"
fi

fi; shard_region_end
# <<< SHARD-END gate-verify-0179


# =============================================================================
# A DEAD SHARD'S LOG IS KEPT (spec 0179; 0168's E-i as ruled). The wrapper refused
# a shard with no totals line correctly, and deleted its log with the scratch, so
# the guest's dead shard left nothing to read. The wrapper is copied beside a stub
# suite whose second shard prints a marker and dies without its totals line.
# =============================================================================
# >>> SHARD-BEGIN dead-shard-0179 cost=1
if shard_region dead-shard-0179; then

DS="$WORK/dead-shard-0179"
rm -rf "$DS"; mkdir -p "$DS/test" "$DS/tmp"
cp "$ROOT/test/run-shards.sh" "$DS/test/run-shards.sh"
# The stub suite the copied wrapper runs, beside it under the name the wrapper expects.
DS_STUB="$DS/test/run-tests"
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  --list-regions) printf "r1\nr2\n" ;;' \
  '  --shard) if [ "$2" = "1/2" ]; then echo "__SHARD__ 1/2 regions=1 of 2"; echo "__REGION__ r1 1 0"; echo "passed 1, failed 0, total 1"; else echo "__SHARD__ 2/2 regions=1 of 2"; echo "dead-shard-marker the last words"; exit 137; fi ;;' \
  'esac' > "$DS_STUB.sh"
DS_ERR="$(TMPDIR="$DS/tmp" bash "$DS/test/run-shards.sh" --shards 2 2>&1 >/dev/null)"; DS_RC=$?
DS_KEPT="$(printf '%s\n' "$DS_ERR" | sed -n 's/.*Its whole log is kept at //p' | head -n 1)"
if [[ "$DS_RC" -ne 0 && "$DS_ERR" == *"shard 2/2 produced no totals line"* && -n "$DS_KEPT" && -f "$DS_KEPT" ]] \
   && grep -q 'dead-shard-marker' "$DS_KEPT"; then
  ok "dead shard a: a shard that died without its totals line is refused and its whole log is kept, the path printed"
else
  bad "dead shard a: a shard that died without its totals line is refused and its whole log is kept, the path printed" "rc=$DS_RC kept=${DS_KEPT:-none} $(printf '%s' "$DS_ERR" | tr '\n' ' ' | cut -c1-200)"
fi
# b: a shard that prints its totals having claimed no region (the guest's shape at
# b85d71b): the unclaimed regions are refused, and that shard's log is kept.
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  --list-regions) printf "r1\nr2\n" ;;' \
  '  --shard) if [ "$2" = "1/2" ]; then echo "__SHARD__ 1/2 regions=1 of 2"; echo "__REGION__ r1 1 0"; echo "passed 1, failed 0, total 1"; else echo "__SHARD__ 2/2 regions=1 of 2"; echo "claimed-none-marker"; echo "passed 0, failed 0, total 0"; fi ;;' \
  'esac' > "$DS_STUB.sh"
DS_ERR="$(TMPDIR="$DS/tmp" bash "$DS/test/run-shards.sh" --shards 2 2>&1 >/dev/null)"; DS_RC=$?
DS_KEPT="$(printf '%s\n' "$DS_ERR" | sed -n 's/.*Its whole log is kept at //p' | head -n 1)"
if [[ "$DS_RC" -ne 0 && "$DS_ERR" == *"region r2 was claimed by NO shard"* && "$DS_ERR" == *"shard 2/2 claimed no region"* && -n "$DS_KEPT" && -f "$DS_KEPT" ]] \
   && grep -q 'claimed-none-marker' "$DS_KEPT"; then
  ok "dead shard b: a shard that printed its totals and claimed no region is named beside the unclaimed region, and its log is kept"
else
  bad "dead shard b: a shard that printed its totals and claimed no region is named beside the unclaimed region, and its log is kept" "rc=$DS_RC kept=${DS_KEPT:-none} $(printf '%s' "$DS_ERR" | tr '\n' ' ' | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END dead-shard-0179

# =============================================================================
# ONE RETRY OF A SHARD THAT DIED BEFORE ITS FIRST CASE, AND EVERY LINE OF A
# FAILURE (spec 0180; the validator's ruling at 0179's close, and 0179's E-j).
# The same method as above: the wrapper copied beside a stub suite. The stub's
# second shard dies with no case line as many times as DS_DEATHS says, counting
# its runs in DS_COUNT, so the retry's two outcomes and the default are driven.
# =============================================================================
# >>> SHARD-BEGIN dead-retry-0180 cost=1
if shard_region dead-retry-0180; then

DR="$WORK/dead-retry-0180"
rm -rf "$DR"; mkdir -p "$DR/test" "$DR/tmp"
cp "$ROOT/test/run-shards.sh" "$DR/test/run-shards.sh"
DR_STUB="$DR/test/run-tests"   # the stub suite, beside the copied wrapper under the name it expects
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  --list-regions) printf "r1\nr2\n" ;;' \
  '  --shard) if [ "$2" = "1/2" ]; then echo "__SHARD__ 1/2 regions=1 of 2"; echo "__REGION__ r1 1 0"; echo "PASS  one"; echo "passed 1, failed 0, total 1"; exit 0; fi' \
  '    n=$(( $(cat "$DS_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$DS_COUNT"' \
  '    echo "Setlist hook suite"; echo "root: /stub"' \
  '    if [ "$n" -le "$DS_DEATHS" ]; then [ -n "${DS_AFTER_CASE:-}" ] && echo "PASS  early"; echo "dead-retry-marker-$n"; exit 137; fi' \
  '    echo "__SHARD__ 2/2 regions=1 of 2"; echo "__REGION__ r2 1 0"; echo "PASS  two"; echo "passed 1, failed 0, total 1" ;;' \
  'esac' > "$DR_STUB.sh"
dr_run() { # dr_run <deaths> [flags...] -> DR_OUT (stdout and stderr), DR_RC, DR_RUNS
  local deaths="$1"; shift
  rm -f "$DR/count"
  DR_OUT="$(DS_COUNT="$DR/count" DS_DEATHS="$deaths" TMPDIR="$DR/tmp" bash "$DR/test/run-shards.sh" --shards 2 "$@" 2>&1)"; DR_RC=$?
  DR_RUNS="$(cat "$DR/count" 2>/dev/null || echo 0)"
}
dr_run 1 --retry-dead
if [[ "$DR_RC" -eq 0 && "$DR_RUNS" -eq 2 && "$DR_OUT" == *"DEAD-SHARD: shard 2/2 died before its first case, retried once"* \
      && "$DR_OUT" == *"| dead-retry-marker-1"* && "$DR_OUT" == *"DEAD-SHARD: shard 2/2 completed on its one retry"* \
      && "$DR_OUT" == *"passed 2, failed 0, total 2"* ]]; then
  ok "dead retry a: with --retry-dead a shard that died before its first case runs once more, its first log printed whole and the sighting named"
else
  bad "dead retry a: with --retry-dead a shard that died before its first case runs once more, its first log printed whole and the sighting named" \
      "rc=$DR_RC runs=$DR_RUNS $(printf '%s' "$DR_OUT" | tr '\n' ' ' | cut -c1-300)"
fi
dr_run 2 --retry-dead
if [[ "$DR_RC" -ne 0 && "$DR_RUNS" -eq 2 && "$DR_OUT" == *"died AGAIN on its one retry"* && "$DR_OUT" == *"| dead-retry-marker-2"* \
      && "$DR_OUT" == *"shard 2/2 produced no totals line"* ]]; then
  ok "dead retry b: a second death is refused as before, by name, with both logs printed and no third run"
else
  bad "dead retry b: a second death is refused as before, by name, with both logs printed and no third run" \
      "rc=$DR_RC runs=$DR_RUNS $(printf '%s' "$DR_OUT" | tr '\n' ' ' | cut -c1-300)"
fi
DS_AFTER_CASE=1 dr_run 1 --retry-dead
if [[ "$DR_RC" -ne 0 && "$DR_RUNS" -eq 1 && "$DR_OUT" == *"died after a case line, which is never retried"* \
      && "$DR_OUT" == *"shard 2/2 produced no totals line"* ]]; then
  ok "dead retry c: a shard that died after a case line is never retried and is refused, its log printed"
else
  bad "dead retry c: a shard that died after a case line is never retried and is refused, its log printed" \
      "rc=$DR_RC runs=$DR_RUNS $(printf '%s' "$DR_OUT" | tr '\n' ' ' | cut -c1-300)"
fi
dr_run 1
if [[ "$DR_RC" -ne 0 && "$DR_RUNS" -eq 1 && "$DR_OUT" != *"DEAD-SHARD:"* && "$DR_OUT" == *"shard 2/2 produced no totals line"* ]]; then
  ok "dead retry d: without the flag the wrapper is unchanged: no retry, the refusal as before"
else
  bad "dead retry d: without the flag the wrapper is unchanged: no retry, the refusal as before" \
      "rc=$DR_RC runs=$DR_RUNS $(printf '%s' "$DR_OUT" | tr '\n' ' ' | cut -c1-300)"
fi
# e: a red shard's failure with several detail lines: --whole-failures prints all of them, the default one.
# Three begin with a word a terminator starts with, spelled as a detail spells it (spec 0180, fix
# round 2, the 2.11.0 leg's F14: the first such line ended the failure and dropped the cause).
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  --list-regions) printf "r1\n" ;;' \
  '  --shard) echo "__SHARD__ $2 regions=1 of 1"; echo "FAIL  three lines"; echo "       first-detail"; echo "second-detail"; echo "PASS 2 of a captured sub-run"; echo "TIME is what the cause was"; echo "passed 3, failed 0 in the nested run"; echo "third-detail"; echo "__REGION__ r1 0 1"; echo "passed 0, failed 1, total 1"; exit 1 ;;' \
  'esac' > "$DR_STUB.sh"
dr_run 0 --whole-failures
DR_W="$DR_OUT"
dr_run 0
if [[ "$DR_W" == *"first-detail"*"second-detail"*"PASS 2 of a captured"*"TIME is what"*"passed 3, failed 0 in"*"third-detail"* && "$DR_W" != *"passed 0, failed 1, total 1"* \
      && "$DR_OUT" == *"first-detail"* && "$DR_OUT" != *"third-detail"* ]]; then
  ok "dead retry e: --whole-failures prints every line of a failure; without it the one detail line as before"
else
  bad "dead retry e: --whole-failures prints every line of a failure; without it the one detail line as before" \
      "whole: $(printf '%s' "$DR_W" | tr '\n' ' ' | cut -c1-200) | default: $(printf '%s' "$DR_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END dead-retry-0180
