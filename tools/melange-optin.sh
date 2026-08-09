#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0

fail() {
  printf 'melange-optin: %s\n' "$1" >&2
  failures=$((failures + 1))
}

melc_rule_count() {
  (opam exec -- dune rules @all 2>/dev/null || true) | grep -c melc || true
}

unset ERR_TRACE_TEST_MELANGE || true
count=$(melc_rule_count)
if [ "$count" -ne 0 ]; then
  fail "disabled configuration scheduled $count melc rule(s)"
fi
if ! opam exec -- dune build @all; then
  fail 'disabled configuration did not build'
fi

melc_path=$(opam exec -- sh -c 'command -v melc' 2>/dev/null || true)
if [ -n "$melc_path" ]; then
  count=$(ERR_TRACE_TEST_MELANGE=true melc_rule_count)
  if [ "$count" -eq 0 ]; then
    fail 'enabled configuration scheduled no melc rules'
  fi
  if ! ERR_TRACE_TEST_MELANGE=true opam exec -- dune build @melange-test; then
    fail 'enabled configuration did not build'
  fi
else
  printf '%s\n' 'melange-optin: melc unavailable; disabled configuration verified'
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

printf '%s\n' 'melange-optin: ok'
