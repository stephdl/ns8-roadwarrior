#!/bin/bash

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Connect an OpenVPN client to the module from a container on the node, then run a command
# inside the client once the tunnel is up.
#
#   vpn-client.sh IMAGE PROFILE [USER PASSWORD] [-- COMMAND...]
#
# Prints "connected" or "refused" and exits 0 when connected, 1 otherwise.
# The client image is the server image of the module: it ships the openvpn binary.

set -u
image=$1
profile=$2
shift 2
user=""
password=""
if [ $# -ge 2 ] && [ "$1" != "--" ]; then
    user=$1
    password=$2
    shift 2
fi
[ "${1:-}" = "--" ] && shift

workdir=$(mktemp -d /var/tmp/rw-client.XXXXXX)
# RW_KEEP_CLIENT=1 leaves the container for the caller, to read its logs
if [ "${RW_KEEP_CLIENT:-}" = 1 ]; then
    # The client still reads its profile: the caller removes the container, /var/tmp is cleaned by the system
    trap '' EXIT
else
    trap 'podman rm -f rw-client >/dev/null 2>&1; rm -rf "${workdir}"' EXIT
fi
cp "${profile}" "${workdir}/client.ovpn"
args=()
if [ -n "${user}" ]; then
    printf '%s\n%s\n' "${user}" "${password}" > "${workdir}/credentials"
    # The profile asks again after a refusal: the test wants the first answer only
    args=(--auth-user-pass /work/credentials --auth-retry none)
fi

podman rm -f rw-client >/dev/null 2>&1
podman run -d --name rw-client --cap-add NET_ADMIN --device /dev/net/tun \
    -v "${workdir}:/work:z" --entrypoint openvpn "${image}" \
    --config /work/client.ovpn "${args[@]}" --verb 3 >/dev/null || exit 1

for _ in $(seq 1 30); do
    logs=$(podman logs rw-client 2>&1)
    if grep -q "Initialization Sequence Completed" <<<"${logs}"; then
        echo connected
        if [ $# -gt 0 ]; then
            podman exec rw-client "$@"
            exit $?
        fi
        exit 0
    fi
    # The server accepted certificate and password, and asks the authenticator code
    if grep -q "AUTH_FAILED,CRV1:" <<<"${logs}"; then
        echo CRV1
        exit 1
    fi
    if grep -qE "AUTH_FAILED|Exiting due to fatal error" <<<"${logs}" || ! podman container exists rw-client \
        || [ "$(podman inspect -f '{{.State.Running}}' rw-client)" != "true" ]; then
        echo refused
        exit 1
    fi
    sleep 1
done
echo refused
exit 1
