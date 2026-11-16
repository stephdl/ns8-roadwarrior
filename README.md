# ns8-roadwarrior

OpenVPN road warrior server for NethServer 8.

Remote users connect to one node. They reach the web apps of that node through Traefik, and the Samba file server of the node if you allow it. The VPN clients get their own private network, so you can keep a web app for them only: paste the VPN network in "Allow access from" of the app HTTP route.

The module is rootless. The core creates the tun device and the firewall zone. Clients do not reach other nodes, the LAN or Internet through the VPN.

## Install

    add-module ghcr.io/stephdl/roadwarrior:latest 1

Install one instance per node that runs apps you want to reach through the VPN.

## Configure

    api-cli run configure-module --agent module/roadwarrior1 --data - <<EOF
    {
      "host": "vpn.example.org",
      "port": 1194,
      "network": "10.8.0.0/24",
      "auth_mode": "certificate_password",
      "user_domain": "ad.example.org",
      "totp_required": false,
      "expose_samba": true
    }
    EOF

`auth_mode` is `certificate` or `certificate_password`. With a password, the user logs in with the user domain password, and an authenticator code (TOTP) can be added per account. `totp_required` refuses the accounts without an authenticator.

The port and the network cannot change while accounts exist. The port is written in every profile, and the network in the HTTP route allowlists.

## Accounts

    api-cli run add-account --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run download-client-config --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run remove-account --agent module/roadwarrior1 --data '{"name": "john"}'

In password mode the account name is a user of the user domain. `remove-account` revokes the certificate and closes the session.

The profile holds the client private key. In certificate mode the profile alone gives access, so send it through a safe channel.

## DNS

A dnsmasq instance listens on the VPN address of the node. It answers the host names of the node HTTP routes with that address, forwards the Samba realm to the domain controller of the node, and resolves the rest through the node. The profile does not hold routes or DNS settings: the server pushes them.

## Uninstall

    remove-module --no-preserve roadwarrior1
