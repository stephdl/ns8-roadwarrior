#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Settings come from /run/ovpn/server.env, written by configure-module.
# The volume /etc/openvpn keeps the PKI and the generated files.

set -e

case "$1" in
s2s|spoke) ;;
*) . /run/ovpn/server.env ;;
esac

data_ciphers="AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305"

case "$1" in
openvpn)
    ovpn-pki init
    mkdir -p /etc/openvpn/run
    if [ "${AUTH_MODE}" = "certificate_password" ]; then
        auth_lines="auth-user-pass-verify /usr/local/bin/ovpn-auth via-file
auth-gen-token 43200 external-auth
auth-gen-token-secret /etc/openvpn/pki/auth-token.key"
    else
        auth_lines=""
    fi
    cat > /etc/openvpn/server.conf <<EOF
dev ${OVPN_TUN}
dev-type tun
topology subnet
server ${OVPN_NETWORK} ${OVPN_NETMASK}
# Kernel DCO needs CAP_NET_ADMIN of the host to add a peer, a rootless module never has it
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
data-ciphers ${data_ciphers}
${auth_lines}
script-security 2
# Pushes the routes and the domains of /run/ovpn/push.json: a change needs no restart
client-connect /usr/local/bin/ovpn-connect
client-disconnect "/usr/local/bin/ovpn-history disconnect"
management /etc/openvpn/run/mgmt.sock unix
status /etc/openvpn/run/status.log 30
keepalive 10 60
persist-key
explicit-exit-notify 1
verb 3
EOF
    exec openvpn --config /etc/openvpn/server.conf
    ;;
s2s)
    # Site-to-site server of a hub, in the network namespace of the hub pod.
    # The nodes join it as clients and get a fixed address from their ccd file.
    . /run/ovpn/s2s.env
    ovpn-pki s2s-init
    mkdir -p /etc/openvpn/run
    # The user tunnel may open connections to the nodes, nothing else crosses the hub:
    # users never reach each other, and a node never opens a connection to a user.
    nft -f - <<EOF
table inet roadwarrior
delete table inet roadwarrior
table inet roadwarrior {
    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        iifname "${RW_TUN}" oifname "${S2S_TUN}" accept
    }
}
EOF
    route_lines=""
    for route in ${S2S_ROUTES}; do
        route_lines="${route_lines}route ${route%/*} ${route#*/}
"
    done
    cat > /etc/openvpn/s2s.conf <<EOF
dev ${S2S_TUN}
dev-type tun
topology subnet
server ${S2S_NETWORK} ${S2S_NETMASK}
port ${S2S_PORT}
proto udp
tls-server
ca /etc/openvpn/s2s-pki/ca.crt
cert /etc/openvpn/s2s-pki/issued/server.crt
key /etc/openvpn/s2s-pki/private/server.key
dh none
crl-verify /etc/openvpn/s2s-pki/crl.pem
remote-cert-tls client
disable-dco
# Only the registered nodes connect, each with the address the hub gave it
client-config-dir /run/ovpn/ccd
ccd-exclusive
data-ciphers ${data_ciphers}
${route_lines}
management /etc/openvpn/run/s2s-mgmt.sock unix
status /etc/openvpn/run/s2s-status.log 10
keepalive 10 60
# Tell the nodes on restart, or they wait for the keepalive timeout to join again
explicit-exit-notify 1
persist-key
verb 3
EOF
    exec openvpn --config /etc/openvpn/s2s.conf
    ;;
spoke)
    # Site-to-site client of a node. The core created its tun with the address the hub gave,
    # so OpenVPN only moves the packets.
    . /run/ovpn/spoke.env
    cat > /tmp/spoke.conf <<EOF
client
dev ${OVPN_TUN}
dev-type tun
proto udp
remote ${SPOKE_REMOTE} ${SPOKE_PORT}
resolv-retry infinite
nobind
ifconfig-noexec
route-noexec
persist-tun
persist-key
remote-cert-tls server
verify-x509-name server name
disable-dco
ca /run/ovpn/spoke-ca.crt
cert /run/ovpn/spoke.crt
key /run/ovpn-secrets/spoke.key
data-ciphers ${data_ciphers}
# Exit instead of a soft restart: systemd starts the client again and reads the address and port
# of the hub again, which a restore or a move of the hub changes
pull-filter ignore "ping-restart"
ping 10
ping-exit 60
verb 3
EOF
    exec openvpn --config /tmp/spoke.conf
    ;;
dnsmasq)
    # Only the VPN clients ask this resolver: it answers on the tun address alone.
    # The names of the hosts file answer with the address of their node, the rest goes to the node resolver.
    # No --bind-dynamic: it may start before OpenVPN creates the tun, and then missed its UDP socket.
    # The wildcard socket of the private namespace needs no tun at start.
    exec dnsmasq --keep-in-foreground --log-facility=- \
        --listen-address="${OVPN_SERVER_IP}" --except-interface=lo \
        --no-hosts --addn-hosts=/run/ovpn/hosts --conf-file=/run/ovpn/dnsmasq.conf
    ;;
*)
    exec "$@"
    ;;
esac
