#!/usr/bin/env bash
# Tests for the UDP GRO forwarding tuning applied at start.
set -e

ROOT="$(dirname "$(dirname "$0")")"
WORKDIR="$(mktemp -d || exit 1)"
trap 'rm -rf ${WORKDIR}' EXIT

# shellcheck source=tests/helpers.sh
. "${ROOT}/tests/helpers.sh"

PACKAGE_ROOT="$(cd "${ROOT}/package" && pwd)"
export PACKAGE_ROOT
export TAILSCALE_ROOT="${WORKDIR}"
export PATH="${WORKDIR}:${PATH}"

mock "${WORKDIR}/sleep" ""
mock "${WORKDIR}/systemctl" "" 0
mock "${WORKDIR}/tailscale" "1.1.0"
mock "${WORKDIR}/ip" "default via 10.0.0.1 dev eth4 proto static"

# ── applied by default, to the default-route device ───────────────────────────
mock "${WORKDIR}/ethtool" "" 0
reset_mock "${WORKDIR}/ethtool"
: > "${TAILSCALE_ROOT}/tailscale-env"
output="$("${PACKAGE_ROOT}/manage.sh" start 2>&1)"
assert_contains "$(cat "${WORKDIR}/ethtool.args")" \
    "^-K eth4 rx-udp-gro-forwarding on rx-gro-list off$" \
    "tuning is applied to the default route device"
assert_contains "$output" "Applied Tailscale's UDP GRO forwarding tuning to eth4" \
    "applying the tuning is reported"

# ── opt out ───────────────────────────────────────────────────────────────────
reset_mock "${WORKDIR}/ethtool"
printf '%s\n' 'TAILSCALE_ETHTOOL_TUNING="false"' > "${TAILSCALE_ROOT}/tailscale-env"
"${PACKAGE_ROOT}/manage.sh" start >/dev/null 2>&1
[[ ! -f "${WORKDIR}/ethtool.args" ]]; assert "TAILSCALE_ETHTOOL_TUNING=false skips the tuning"

# ── explicit device override ──────────────────────────────────────────────────
reset_mock "${WORKDIR}/ethtool"
: > "${TAILSCALE_ROOT}/tailscale-env"
TAILSCALE_ETHTOOL_DEVICE="br0" "${PACKAGE_ROOT}/manage.sh" start >/dev/null 2>&1
assert_contains "$(cat "${WORKDIR}/ethtool.args")" "^-K br0 " \
    "TAILSCALE_ETHTOOL_DEVICE overrides device detection"

# ── a NIC that does not support the features must not fail the start ──────────
reset_mock "${WORKDIR}/ethtool"
mock "${WORKDIR}/ethtool" "" 1
output="$("${PACKAGE_ROOT}/manage.sh" start 2>&1)"
assert_contains "$output" "Tailscaled started successfully" \
    "an unsupported NIC does not fail the start"
assert_contains "$output" "Could not apply UDP GRO forwarding tuning" \
    "an unsupported NIC is reported"

# ── no default route must not fail the start ──────────────────────────────────
reset_mock "${WORKDIR}/ethtool"
mock "${WORKDIR}/ethtool" "" 0
mock "${WORKDIR}/ip" ""
output="$("${PACKAGE_ROOT}/manage.sh" start 2>&1)"
assert_contains "$output" "Could not determine the default route device" \
    "a missing default route is reported"
assert_contains "$output" "Tailscaled started successfully" \
    "a missing default route does not fail the start"
