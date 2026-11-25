# ns8-roadwarrior

OpenVPN road warrior server for NethServer 8.

Remote users connect to one node, the hub. They reach the web apps of that node through Traefik, and the Samba file server of the node if you allow it. Other nodes join the hub to be reached the same way. The VPN clients get their own private network, so you can keep a web app for them only: paste the VPN network in "Allow access from" of the app HTTP route.

See [docs/network.md](docs/network.md) for diagrams of the network path, the login and the DNS.

The module is rootless. The core creates the tun device, the firewall zone and the public UDP port. Clients do not reach the LAN or Internet through the VPN. They reach the nodes that [joined the hub](docs/network.md#a-hub-and-its-nodes).

The VPN zone opens 80/tcp, 443/tcp and 53/tcp+udp of the node, plus the Samba ports when `expose_samba` is on. SSH from the VPN network is rejected, unless `expose_ssh` is on. The SSH port is the one where sshd answers, among the ports the node firewall opens.

## Install

    add-module ghcr.io/stephdl/roadwarrior:latest 1

The module pulls a second image, `ghcr.io/stephdl/roadwarrior-server`, that runs OpenVPN and dnsmasq.

Install one instance per node that runs apps you want to reach through the VPN.

Debian 13 does not work for now. With kernel 6.12.117 a rootless container cannot open a tun that has no owner, so OpenVPN fails with `Cannot ioctl TUNSETIFF ...: Operation not permitted`. The bug is NethServer/dev#8334, tracked here in #16. The fix is NethServer/ns8-core#1422: once a core with it is released, the module requires that core and Debian 13 works. Rocky Linux 9 is not affected.

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

`host`, `port`, `network` and `auth_mode` are required, except for a node of a hub.

- `mode`: `hub` (default) or `spoke`. See [A hub and its nodes](docs/network.md#a-hub-and-its-nodes).
- `hub`: with `spoke`, the instance of the hub this node joins. A spoke sends only `mode`, `hub`, `expose_samba` and `expose_ssh`.

- `host`: name or address the clients connect to. The first time, the UI proposes the node FQDN.
- `port`: UDP port, from 1024 to 65535.
- `network`: private IPv4 network from /16 to /28. The hub also takes the network next to it to link the nodes, so that pair must not overlap the cluster network or a node interface, and both halves must be private.
- `auth_mode`: `certificate`, or `certificate_password` to also check the user domain password.
- `user_domain`: required with `certificate_password`.
- `totp_required`: refuse the accounts without an authenticator. Needs `certificate_password`.
- `expose_samba`: open the ports of the Samba domain controller of the node, and push a route to it.
- `expose_ssh`: accept SSH from the users. See [Where the packets can go](docs/network.md#where-the-packets-can-go).

Validation errors: `invalid_network`, `network_not_allowed`, `network_overlap`, `link_not_private` (the network next to it is public, as with `192.168.0.0/16`), `user_domain_required`, `user_domain_not_found`, `totp_needs_password`, `hub_not_found`, `not_joined` (send the answer of add-spoke as join), `link_overlap` (the link network of the hub overlaps a network of this node), `accounts_exist` (a spoke has no users), `hub_has_spokes` (remove the other nodes before leaving the hub role or changing its network).

Every configured instance is a hub unless it joins another one. The UI joins the other nodes in one save. From the command line, carry the request of the node to the hub, then the answer back:

    csr=$(api-cli run request-spoke-certificate --agent module/roadwarrior2 | jq .csr)
    join=$(api-cli run add-spoke --agent module/roadwarrior1 --data "{\"module_id\": \"roadwarrior2\", \"csr\": $csr}")
    api-cli run configure-module --agent module/roadwarrior2 --data "{\"mode\": \"spoke\", \"hub\": \"roadwarrior1\", \"expose_samba\": true, \"join\": $join}"

`add-spoke` signs only a request made by that instance: a request named after another one fails with `csr_mismatch`.

`list-spokes` on the hub lists the nodes, what each one shares, read from the settings of the node, and the state of their link. `remove-spoke` with `{"module_id": "roadwarrior2"}` removes one.

While accounts exist, `host`, `port`, `network` and `auth_mode` cannot change. The errors are `host_locked`, `port_locked`, `network_locked` and `auth_mode_locked`. Host, port and login prompt are written in every profile already sent, and the network in the HTTP route allowlists. Remove all the accounts to change them.

## Accounts

    api-cli run add-account --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run list-accounts --agent module/roadwarrior1
    api-cli run download-client-config --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run kill-session --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run remove-account --agent module/roadwarrior1 --data '{"name": "john"}'

Names match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`, and `server` is reserved. In password mode, use the user name of the user domain: the login must match the certificate name.

`remove-account` revokes the certificate and closes the session.

`kill-session` closes the open session and tells the client to stop instead of reconnecting. The session token of the account stops working too, so the user must type the password and the authenticator code again. It returns `no_session` if the account is not connected.

    api-cli run disable-account --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run enable-account --agent module/roadwarrior1 --data '{"name": "john"}'

`disable-account` closes the session and refuses every new one, in every authentication mode. The certificate stays valid, so `enable-account` gives the access back with the same profile. A disabled account cannot get, confirm or reset an authenticator, nor renew its certificate.

    api-cli run renew-account --agent module/roadwarrior1 --data '{"name": "john"}'

`renew-account` revokes the certificate of an enabled account, issues a new one and closes the session. The authenticator and the login history stay. The profile already sent stops working, so send the new one. Use it when a laptop is lost but the account must stay.

Certificates and the revocation list last 10 years, the CA 20 years. The status page warns 90 days before the CA expires.

`list-accounts` returns the certificate status, the authenticator status, the session state, the disabled flag and the last login time of each account. The search of the accounts page matches the names and the states shown in the row, in the language of the page.

## Profile

`download-client-config` returns the file name `NAME@HOST.ovpn` and the profile. The profile holds the CA, the client certificate and key, and the tls-crypt key. Routes and DNS settings are not in the profile: the server pushes them.

With `"format": "zip"` it returns a zip archive instead, base64 encoded. The archive holds the same profile, the keys as separate files (`ca.crt`, `NAME.crt`, `NAME.key`, `tls-crypt.key`) and a second profile that points to those files. Use it when a client asks for each file apart, like the GNOME network settings.

In password mode the profile asks for the user name and the password. The authenticator code is not in the profile: the server asks it when the account has one, so the profile keeps working when an authenticator is set up later.

In certificate mode the profile alone gives access. Send it through a safe channel.

`download-client-config` and `enroll-totp` encrypt their output for the browser that sends a `public_key`, as the UI does: the core keeps task output in Redis for some hours, and only ciphertext lands there. Without `public_key`, the output is in plain text. Use that form only to troubleshoot: Redis replicates it to every node, so the client key or the TOTP secret stays readable there. Prefer the UI to hand a profile or a secret to a user.

## Clients

Import the `.ovpn` file in an OpenVPN client:

- Windows, macOS, iOS, Android: OpenVPN Connect, https://openvpn.net/client/
- Windows: OpenVPN GUI from OpenVPN community, https://openvpn.net/community-downloads/
- macOS: Tunnelblick, https://tunnelblick.net/
- Linux: NetworkManager with the OpenVPN plugin, or the `openvpn` command

The VPN carries only the network of the VPN and the names of the node. NetworkManager does not follow the routes of the server: after the import, it sends all the traffic into the tunnel, and the client loses Internet. In the IPv4 settings of the connection, check "Use this connection only for resources on its network", or run:

    nmcli connection modify "NAME@HOST" ipv4.never-default yes ipv6.never-default yes

OpenVPN Connect, OpenVPN GUI and Tunnelblick follow the server and need no change.

The server runs OpenVPN 2.7. Split DNS needs a 2.6 or newer client. Older clients still connect but may not use the VPN resolver.

In password mode the client asks for the user name and the domain password. When the account has an authenticator, the server checks the password, then answers with an OpenVPN dynamic challenge (CRV1). The client opens a second prompt "Authenticator code" and connects again with the 6 digits. The code is never appended to the password. A pending challenge lasts 3 minutes and works once: a wrong code sends the user back to the password.

NetworkManager, OpenVPN Connect, OpenVPN GUI and Tunnelblick handle the dynamic challenge. The `openvpn` command line client handles it with `auth-retry interact`, which the profile sets.

The module was tested with the `openvpn` 2.7 command line client and its management interface, which is the path the graphical clients use.

## Authenticator (TOTP)

    api-cli run enroll-totp --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run confirm-totp --agent module/roadwarrior1 --data '{"name": "john", "code": "123456"}'
    api-cli run reset-totp --agent module/roadwarrior1 --data '{"name": "john"}'

`enroll-totp` returns a new secret and its `otpauth://` URI. The previous secret stays active until `confirm-totp` accepts a code from the new one.

Codes use SHA-1, 6 digits and 30 second steps, with one step of tolerance on each side. A code works once. It is spent only when the password is right.

After a full login, the server gives the client a session token valid for 12 hours. Renegotiations and short reconnects use it, so the user is not asked again.

## Login history

    api-cli run get-login-history --agent module/roadwarrior1 --data '{"name": "john"}'
    api-cli run get-login-history --agent module/roadwarrior1 --data '{}'

Without a name it returns the events of every account. It returns the logins, the logouts and the refused attempts, newest first. A logout holds the session duration and the traffic. A refusal holds a reason: `wrong_password`, `wrong_code`, `challenge_expired`, `code_reused`, `account_disabled`, `totp_not_enrolled`, `certificate_mismatch` or `error`.

The history keeps the last 15000 events of the instance, trimmed when the file passes 4 MB. The accounts page shows it per account with a date filter, and downloads it as JSON, per account or for every account.

## DNS

A dnsmasq instance listens on the VPN address of the node. It answers the host names of the node HTTP routes and the FQDN of the node with that address, and forwards the Samba realm to the domain controller of the node. Other names go to the resolver of the node.

The host of the VPN server is never answered with the VPN address, so a client can always reconnect. Use a dedicated name for it, like `vpn.example.org`: if it is the FQDN of the node, cluster-admin on that name stays outside the tunnel.

See [Use the VPN](docs/network.md#use-the-vpn) to check that the traffic of a client goes through the tunnel.

A web app of another node of the cluster can be kept for the VPN clients with two HTTP routes, see [A web app of another node](docs/network.md#a-web-app-of-another-node).

## Status

`get-vpn-status` returns whether the server runs, the open sessions and the CA expiry date. The Sessions page lists the open sessions, refreshes every 30 seconds and can disconnect one.

## Backup, restore, clone and move

The backup holds the settings, the PKI with the revocation list, the accounts, the authenticator secrets, the used codes and the login history. A restore, a clone or a move runs `configure-module` again with the saved settings: it creates the tun, the firewall zone and the public port on the target node.

The CA is the same, so the profiles already sent stay valid. They point to the old host until the host name points to the new node.

On the same node as the original instance, the copy cannot take the same port and network. It stays stopped and logs the conflict. When the original is removed, the copy starts on its own: a restore or a move with "replace" ends that way. After a plain clone, remove the original or change the settings of the copy. A clone of a node of a hub does not reuse the join of its original: join it again. A node restored before its hub stays stopped and starts when the hub is configured.

## User interface

The pages are Status, Accounts, Sessions, Nodes, Settings and About. The Nodes page of a hub lists its nodes, with a search. On a node of a hub, Accounts, Sessions and Nodes stay in the menu but show no table: a button opens the same page on the hub. The UI ships in English, German, Spanish, Basque, French, Italian, Portuguese and Brazilian Portuguese.

## Uninstall

    remove-module --no-preserve roadwarrior1
