# ns8-roadwarrior

OpenVPN road warrior server for NethServer 8.

Remote users connect to one node. They reach the web apps of that node through Traefik, and the Samba file server of the node if you allow it. The VPN clients get their own private network, so you can keep a web app for them only: paste the VPN network in "Allow access from" of the app HTTP route.

See [docs/network.md](docs/network.md) for diagrams of the network path, the login and the DNS.

The module is rootless. The core creates the tun device, the firewall zone and the public UDP port. Clients do not reach other nodes, the LAN or Internet through the VPN.

The VPN zone opens 80/tcp, 443/tcp and 53/tcp+udp of the node, plus the Samba ports when `expose_samba` is on. SSH from the VPN network is rejected.

## Install

    add-module ghcr.io/stephdl/roadwarrior:latest 1

The module pulls a second image, `ghcr.io/stephdl/roadwarrior-server`, that runs OpenVPN and dnsmasq.

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

`host`, `port`, `network` and `auth_mode` are required.

- `host`: name or address the clients connect to. The first time, the UI proposes the node FQDN.
- `port`: UDP port, from 1024 to 65535.
- `network`: private IPv4 network from /16 to /28. It must not overlap the cluster network or a node interface.
- `auth_mode`: `certificate`, or `certificate_password` to also check the user domain password.
- `user_domain`: required with `certificate_password`.
- `totp_required`: refuse the accounts without an authenticator. Needs `certificate_password`.
- `expose_samba`: open the ports of the Samba domain controller of the node, and push a route to it.

Validation errors: `invalid_network`, `network_not_allowed`, `network_overlap`, `user_domain_required`, `user_domain_not_found`, `totp_needs_password`.

While accounts exist, `host`, `port`, `network` and `auth_mode` cannot change. The errors are `host_locked`, `port_locked`, `network_locked` and `auth_mode_locked`. Host, port and login prompt are written in every profile already sent, and the network in the HTTP route allowlists. Remove all the accounts to change them.

## Accounts

    api-cli run add-account --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run list-accounts --agent module/roadwarrior1
    api-cli run download-client-config --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run kill-session --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run remove-account --agent module/roadwarrior1 --data '{"name": "john"}'

Names match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`, and `server` is reserved. In password mode, use the user name of the user domain: the login must match the certificate name.

`remove-account` revokes the certificate and closes the session. `kill-session` returns `no_session` if the account is not connected.

`list-accounts` returns the certificate status, the authenticator status, the session state and the last login time of each account.

## Profile

`download-client-config` returns the file name `NAME@HOST.ovpn` and the profile. The profile holds the CA, the client certificate and key, and the tls-crypt key. Routes and DNS settings are not in the profile: the server pushes them.

In password mode the profile asks for the user name and the password. The authenticator code is not in the profile: the server asks it when the account has one, so the profile keeps working when an authenticator is set up later.

In certificate mode the profile alone gives access. Send it through a safe channel.

The UI encrypts the profile and the authenticator secret for the browser: the core keeps task output in Redis for hours, and only ciphertext lands there. Called from `api-cli` without `public_key`, the actions return plain text.

## Clients

Import the `.ovpn` file in an OpenVPN client:

- Windows, macOS, iOS, Android: OpenVPN Connect, https://openvpn.net/client/
- Windows: OpenVPN GUI from OpenVPN community, https://openvpn.net/community-downloads/
- macOS: Tunnelblick, https://tunnelblick.net/
- Linux: NetworkManager with the OpenVPN plugin, or the `openvpn` command

The server needs OpenVPN 2.6 features for split DNS. Older clients still connect but may not use the VPN resolver.

In password mode the client asks for the user name and the domain password. When the account has an authenticator, the server checks the password, then answers with an OpenVPN dynamic challenge (CRV1). The client opens a second prompt "Authenticator code" and connects again with the 6 digits. The code is never appended to the password. A pending challenge lasts 3 minutes and works once: a wrong code sends the user back to the password.

NetworkManager, OpenVPN Connect, OpenVPN GUI and Tunnelblick handle the dynamic challenge. The `openvpn` command line client handles it with `auth-retry interact`, which the profile sets.

Profiles made before this change ask for the code up front with `static-challenge`. The server still accepts them.

The module was tested with the `openvpn` 2.6 command line client and its management interface, which is the path the graphical clients use.

## Authenticator (TOTP)

    api-cli run enroll-totp --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run confirm-totp --agent module/roadwarrior1 --data '{"name": "john", "code": "123456"}'
    api-cli run reset-totp --agent module/roadwarrior1 --data '{"name": "john"}'

`enroll-totp` returns a new secret and its `otpauth://` URI. The previous secret stays active until `confirm-totp` accepts a code from the new one.

Codes use SHA-1, 6 digits and 30 second steps, with one step of tolerance on each side. A code works once. It is spent only when the password is right.

After a full login, the server gives the client a session token valid for 12 hours. Renegotiations and short reconnects use it, so the user is not asked again.

## Login history

    api-cli run get-login-history --agent module/roadwarrior1 --data '{"name": "john"}'

It returns the logins, the logouts and the refused attempts, newest first. A logout holds the session duration and the traffic. A refusal holds a reason: `wrong_password`, `wrong_code`, `challenge_expired`, `code_reused`, `totp_not_enrolled`, `certificate_mismatch`, `malformed_response` or `error`.

The history keeps the last 15000 to 20000 events of the instance. The UI shows it per account and can download it as JSON.

## DNS

A dnsmasq instance listens on the VPN address of the node. It answers the host names of the node HTTP routes and the FQDN of the node with that address, and forwards the Samba realm to the domain controller of the node. Other names go to the resolver of the node.

The host of the VPN server is never answered with the VPN address, so a client can always reconnect. Use a dedicated name for it, like `vpn.example.org`: if it is the FQDN of the node, cluster-admin on that name stays outside the tunnel.

See [Use the VPN](docs/network.md#use-the-vpn) to check that the traffic of a client goes through the tunnel.

## Status

`get-vpn-status` returns whether the server runs, the open sessions and the CA expiry date. The UI warns 90 days before the CA expires.

## Backup, restore, clone and move

The backup holds the settings, the PKI with the revocation list, the accounts, the authenticator secrets, the used codes and the login history. A restore, a clone or a move runs `configure-module` again with the saved settings: it creates the tun, the firewall zone and the public port on the target node.

The CA is the same, so the profiles already sent stay valid. They point to the old host until the host name points to the new node.

On the same node as the original instance, the copy cannot take the same port and network. It stays stopped and logs the conflict. Remove the original, then save the settings of the copy again.

## Uninstall

    remove-module --no-preserve roadwarrior1
