#!/usr/bin/env bash
# =============================================================================
# Guards the two invariants that keep the GitLab templates and the GitHub
# Action interchangeable:
#
#   1. every artifact pins exactly the scanner image declared in VERSION;
#   2. every ARK_IN_* an artifact sets is actually consumed downstream.
#
# Run it locally with: ./scripts/check-sync.sh
#
# Membership tests use bash string matching rather than a grep per name: the
# check runs hundreds of them and process creation dominates on Windows.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0
ok() { printf '  ok   %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*" >&2; failures=$((failures + 1)); }

# Membership test over a newline-separated list.
has_line() {
  local list="$1" needle="$2"
  [[ $'\n'"$list"$'\n' == *$'\n'"$needle"$'\n'* ]]
}

# -----------------------------------------------------------------------------
# Reads KEY=value from the VERSION file.
# -----------------------------------------------------------------------------
version_field() {
  local key="$1" value
  value="$(grep -E "^${key}=" VERSION | head -n1 | cut -d= -f2-)"
  [ -n "$value" ] || { printf 'VERSION is missing %s\n' "$key" >&2; exit 1; }
  printf '%s' "$value"
}

SCANNER_IMAGE="$(version_field SCANNER_IMAGE)"
SCANNER_VERSION="$(version_field SCANNER_VERSION)"

# -----------------------------------------------------------------------------
# Prints the quoted default that follows a key, searching a few lines ahead.
# -----------------------------------------------------------------------------
default_after() {
  local file="$1" key="$2" span="${3:-4}"
  grep -A"$span" -E "^[[:space:]]*${key}:[[:space:]]*$" "$file" |
    grep -m1 -E "^[[:space:]]*default:" |
    sed -E 's/.*default:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/'
}

expect_pin() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    ok "$label"
  else
    fail "$label is '$actual', expected '$expected'"
  fi
}

echo "VERSION pins ${SCANNER_IMAGE}:${SCANNER_VERSION}"
echo
echo "1. image pinning"

for template in templates/*.yml; do
  expect_pin "$template scanner_image" "$(default_after "$template" scanner_image)" "$SCANNER_IMAGE"
  expect_pin "$template scanner_version" "$(default_after "$template" scanner_version)" "$SCANNER_VERSION"
done

expect_pin "action.yml scanner-image" "$(default_after action.yml scanner-image)" "$SCANNER_IMAGE"
expect_pin "action.yml scanner-version" "$(default_after action.yml scanner-version)" "$SCANNER_VERSION"

# The runner script carries its own fallbacks for direct invocation.
runner="$(cat src/run-scanner.sh)"

if [[ $runner == *"ARK_SCANNER_IMAGE:-${SCANNER_IMAGE}}"* ]]; then
  ok "src/run-scanner.sh scanner image fallback"
else
  fail "src/run-scanner.sh scanner image fallback does not match '$SCANNER_IMAGE'"
fi

if [[ $runner == *"ARK_SCANNER_VERSION:-${SCANNER_VERSION}}"* ]]; then
  ok "src/run-scanner.sh scanner version fallback"
else
  fail "src/run-scanner.sh scanner version fallback does not match '$SCANNER_VERSION'"
fi

# -----------------------------------------------------------------------------
# Lists the bare variable names passed to a forwarding helper, following
# backslash continuations. Used for both ark_apply_inputs (templates) and
# add_env_from_input (runner script).
# -----------------------------------------------------------------------------
forwarded_names() {
  awk -v fn="$2" '
    {
      line = $0
      if (index(line, fn) > 0) { inblock = 1 }
      if (inblock) {
        cont = (line ~ /\\[ \t]*$/)
        sub(fn, "", line)
        gsub(/\\/, "", line)
        n = split(line, parts, /[ \t]+/)
        for (i = 1; i <= n; i++) {
          if (parts[i] ~ /^[A-Z][A-Z0-9_]*$/) { print parts[i] }
        }
        if (!cont) { inblock = 0 }
      }
    }
  ' "$1" | sort -u
}

echo
echo "2. ARK_IN_* wiring in templates"

for template in templates/*.yml; do
  content="$(cat "$template")"
  declared="$(grep -oE '^[[:space:]]+ARK_IN_[A-Z0-9_]+:' "$template" | tr -d ' :' | sort -u)"
  used_direct="$(grep -oE 'ARK_IN_[A-Z0-9_]+' "$template" | sort -u)"
  exported="$(forwarded_names "$template" ark_apply_inputs | sed 's/^/ARK_IN_/')"

  template_ok=1

  # Anything the job script references must be declared under variables:.
  for name in $used_direct; do
    if ! has_line "$declared" "$name"; then
      fail "$template uses $name but never declares it under variables:"
      template_ok=0
    fi
  done

  # Anything declared must be read directly or exported by ark_apply_inputs.
  for name in $declared; do
    if has_line "$exported" "$name"; then
      continue
    fi
    if [[ $content == *"\${${name}"* ]]; then
      continue
    fi
    fail "$template declares $name but never reads or exports it"
    template_ok=0
  done

  [ "$template_ok" -eq 1 ] && ok "$template"
done

echo
echo "3. ARK_IN_* wiring between action.yml and src/run-scanner.sh"

action_ok=1
runner_forwarded="$(forwarded_names src/run-scanner.sh add_env_from_input | sed 's/^/ARK_IN_/')"

for name in $(grep -oE 'ARK_IN_[A-Z0-9_]+' action.yml | sort -u); do
  # Either referenced verbatim, or forwarded as a bare name to add_env_from_input.
  if [[ $runner == *"$name"* ]]; then
    continue
  fi
  if has_line "$runner_forwarded" "$name"; then
    continue
  fi
  fail "action.yml sets $name but src/run-scanner.sh never forwards it"
  action_ok=0
done
[ "$action_ok" -eq 1 ] && ok "action.yml -> src/run-scanner.sh"

echo
if [ "$failures" -gt 0 ]; then
  printf '%s check(s) failed\n' "$failures" >&2
  exit 1
fi
echo "all checks passed"
