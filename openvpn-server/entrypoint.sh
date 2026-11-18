#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Settings come from /run/ovpn/server.env, written by configure-module.
# The volume /etc/openvpn keeps the PKI and the generated files.
# OpenVPN starts as root to open the tun, then runs as the user "ovpn" of the mounted
# /etc/passwd. The host prepares db/ for that user before the start (ovpn-write-runtime).

set -e

. /run/ovpn/server.env

case "$1" in
openvpn)
    ovpn-pki init
    # Root without DAC_OVERRIDE: the dirs on the path to crl.pem must stay readable after the drop
    chmod 0755 /etc/openvpn/pki
    mkdir -p -m 0755 /etc/openvpn/run
    if [ "${AUTH_MODE}" = "certificate_password" ]; then
        auth_lines="auth-user-pass-verify /usr/local/bin/ovpn-auth via-file
auth-gen-token 43200 external-auth
auth-gen-token-secret /etc/openvpn/pki/auth-token.key"
    else
        auth_lines=""
    fi
    # PUSH_ROUTES holds address/netmask pairs
    push_lines=""
    for route in ${PUSH_ROUTES}; do
        push_lines="${push_lines}push \"route ${route%/*} ${route#*/}\"
"
    done
    # Clients before 2.6 send every query to the VPN resolver, 2.6 and later only the listed domains
    dns_lines="push \"dhcp-option DNS ${OVPN_SERVER_IP}\"
push \"dns server 0 address ${OVPN_SERVER_IP}\""
    if [ -n "${DNS_DOMAINS}" ]; then
        dns_lines="${dns_lines}
push \"dns server 0 resolve-domains ${DNS_DOMAINS}\""
        # OpenVPN 2.7 clients rebuild the DOMAIN options of their up script from
        # search-domains only, and NetworkManager reads those to route the domains
        dns_lines="${dns_lines}
push \"dns search-domains ${DNS_DOMAINS}\""
        # Older clients, NetworkManager and Windows route these domains to the VPN resolver
        for domain in ${DNS_DOMAINS}; do
            dns_lines="${dns_lines}
push \"dhcp-option DOMAIN ${domain}\""
        done
    fi
    cat > /etc/openvpn/server.conf <<EOF
dev ${OVPN_TUN}
dev-type tun
topology subnet
server ${OVPN_NETWORK} ${OVPN_NETMASK}
# The tun is opened once as root: a SIGHUP would reopen it without the rights, never send one
persist-tun
user ovpn
group ovpn
# Kernel DCO creates its own kind of interface, keep the plain tun
disable-dco
port ${OVPN_PORT}
proto udp
# Reply from the address the client contacted: the node can hold several addresses
multihome
tls-server
ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/issued/server.crt
key /etc/openvpn/pki/private/server.key
dh none
tls-crypt /etc/openvpn/pki/tls-crypt.key
crl-verify /etc/openvpn/pki/crl.pem
remote-cert-tls client
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
${auth_lines}
script-security 2
client-connect /usr/local/bin/ovpn-connect
client-disconnect "/usr/local/bin/ovpn-history disconnect"
${push_lines}${dns_lines}
management /etc/openvpn/run/mgmt.sock unix
# The socket is world-writable: only root, through podman exec, may drive it
management-client-user root
status /etc/openvpn/run/status.log 30
keepalive 10 60
# OpenVPN 2.6 rereads the keys on a soft restart, which fails once root is dropped
persist-key
tmp-dir /tmp
explicit-exit-notify 1
verb 3
EOF
    exec openvpn --config /etc/openvpn/server.conf
    ;;
dnsmasq)
    # Only the VPN clients ask this resolver: it listens on the tun address alone.
    # The names of the hosts file answer with the tun address, the rest goes to the node resolver.
    # It drops root to its own user once the port is bound. No pid file on a read-only root.
    exec dnsmasq --keep-in-foreground --log-facility=- --user=dnsmasq --pid-file= \
        --listen-address="${OVPN_SERVER_IP}" --bind-dynamic --except-interface=lo \
        --no-hosts --addn-hosts=/run/ovpn/hosts --conf-file=/run/ovpn/dnsmasq.conf
    ;;
*)
    exec "$@"
    ;;
esac
