#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

"""Shared helpers of the OpenVPN module. Every path is relative to the module state directory."""

import base64
import fcntl
import ipaddress
import json
import os
import re
import shlex
import socket
import subprocess
import sys
from datetime import datetime, timezone

import agent
from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import agent.ldapproxy

CONTAINER = "openvpn-server"
RUNTIME_DIR = "ovpn"
SERVER_ENV = "ovpn/server.env"
AUTH_JSON = "ovpn/auth.json"
HOSTS = "ovpn/hosts"
DNSMASQ_CONF = "ovpn/dnsmasq.conf"
# Read by the server at each new session: a change needs no restart
DISABLED = "ovpn/disabled.json"
# Left by a restored or moved copy that waits for the original to leave the node
WAITING = "waiting-for-original"
LDAP_PASSWORD = "secrets/ldap-bind-password"
TOTP_FILE = "secrets/totp.json"
ACCOUNTS = "accounts.json"

SETTINGS_DEFAULTS = {
    "OVPN_HOST": "",
    "OVPN_PORT": "1194",
    "OVPN_NETWORK": "10.8.0.0/24",
    "OVPN_AUTH_MODE": "certificate_password",
    "OVPN_USER_DOMAIN": "",
    "OVPN_TOTP_REQUIRED": "False",
    "OVPN_EXPOSE_SAMBA": "False",
}

# Ports of samba, from ns8-samba create-module/70firewall
SAMBA_PORTS = [
    "53/tcp", "53/udp", "88/tcp", "88/udp", "135/tcp", "137/udp", "138/udp", "139/tcp",
    "389/tcp", "389/udp", "445/tcp", "464/tcp", "464/udp", "636/tcp", "3268/tcp", "3269/tcp",
    "49152-65535/tcp",
]
# Traefik for the web apps, the VPN resolver for the names
BASE_PORTS = ["80/tcp", "443/tcp", "53/tcp", "53/udp"]


def log(*args):
    print(*args, file=sys.stderr)


def write_private(path, text):
    os.makedirs(os.path.dirname(path) or ".", mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def save_json(path, data, private=False):
    text = json.dumps(data, indent=2, sort_keys=True)
    if private:
        write_private(path, text)
    else:
        write_text(path, text)


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def settings(env=None):
    env = os.environ if env is None else env
    return {key: env.get(key) or default for key, default in SETTINGS_DEFAULTS.items()}


def is_true(value):
    return str(value) == "True"


def tun_name():
    # Interface names stop at 15 characters, firewalld zone names at 17.
    # Keep the instance number: roadwarrior1 and roadwarrior12 must not share a tun.
    module_id = os.environ["MODULE_ID"]
    number = re.search(r"\d*$", module_id).group()
    return "tunrw" + number if number else ("tun" + module_id)[:15]


def network_parts(cidr):
    net = ipaddress.ip_network(cidr, strict=True)
    server_ip = str(next(net.hosts()))
    return net, server_ip


def is_configured():
    return bool(os.environ.get("OVPN_HOST"))


def samba_on_node(rdb, node_id):
    """Return (module_id, realm, ip) of the samba DC of this node, or None."""
    for key in rdb.scan_iter("module/*/environment"):
        module_id = key.split("/")[1]
        env = rdb.hgetall(key)
        if env.get("NODE_ID") == str(node_id) and env.get("REALM") and env.get("IPADDRESS") \
                and "account_provider" in rdb.smembers(f"module/{module_id}/flags"):
            return module_id, env["REALM"].lower(), env["IPADDRESS"]
    return None


def traefik_hosts(rdb, node_id):
    traefik = rdb.get(f"node/{node_id}/default_instance/traefik")
    if not traefik:
        return []
    return sorted(rdb.smembers(f"module/{traefik}/hosts"))


def firewall_ports(expose_samba):
    ports = list(BASE_PORTS)
    if expose_samba:
        ports += [p for p in SAMBA_PORTS if p not in ports]
    return ports


def write_text(path, text):
    # The containers read these files at any time: never let them see a half written one
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def vpn_domains(hosts, vpn_host):
    """Domains the clients send to the VPN resolver, for the given host names.

    The parent domain of the node groups the apps under one domain, so a new app needs no
    new push. A domain that would also catch the VPN host is never pushed: a reconnect must
    resolve the server outside the tunnel. Host names outside the node domain go one by one,
    which also keeps a public suffix like co.uk out of the list.
    """
    node = socket.getfqdn().lower()
    base = node.split(".", 1)[1] if node.count(".") >= 2 else ""

    def catches_vpn_host(domain):
        return vpn_host == domain or vpn_host.endswith("." + domain)

    domains = set()
    for host in hosts:
        if base and host.endswith("." + base) and not catches_vpn_host(base):
            domains.add(base)
        elif catches_vpn_host(host):
            log(agent.SD_WARNING + f"{host} is not resolved through the VPN: it would catch the VPN host {vpn_host}")
        else:
            domains.add(host)
    return domains


def write_runtime(rdb=None):
    """Write the files read by the server container: server.env, auth.json, the resolver files and the LDAP password."""
    # disabled.json comes from accounts.json: read and write them under the same lock as the actions
    lock_state()
    rdb = rdb or agent.redis_connect(use_replica=True)
    conf = settings()
    node_id = os.environ["NODE_ID"]
    net, server_ip = network_parts(conf["OVPN_NETWORK"])
    samba = samba_on_node(rdb, node_id) if is_true(conf["OVPN_EXPOSE_SAMBA"]) else None
    # The node name serves cluster-admin and path routes: it must enter the tunnel too.
    # The VPN host stays out, or a reconnect would look for the server inside the tunnel.
    vpn_host = conf["OVPN_HOST"].lower()
    hosts = sorted(
        {h.lower() for h in traefik_hosts(rdb, node_id) + [socket.getfqdn()] if "." in h} - {vpn_host}
    )

    push_routes = []
    domains = vpn_domains(hosts, vpn_host)
    if samba:
        push_routes.append(f"{samba[2]}/255.255.255.255")
        domains.add(samba[1])
    domains = sorted(domains)

    try:
        with open(SERVER_ENV) as f:
            old_server_env = f.read()
    except FileNotFoundError:
        old_server_env = ""
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    server_env = {
        "OVPN_TUN": os.environ["OVPN_TUN"],
        "OVPN_NETWORK": str(net.network_address),
        "OVPN_NETMASK": str(net.netmask),
        "OVPN_SERVER_IP": server_ip,
        "OVPN_PORT": conf["OVPN_PORT"],
        "OVPN_REMOTE": conf["OVPN_HOST"],
        "OVPN_CA_CN": f"{os.environ['MODULE_ID']} {conf['OVPN_HOST']}",
        "AUTH_MODE": conf["OVPN_AUTH_MODE"],
        "PUSH_ROUTES": " ".join(push_routes),
        "DNS_DOMAINS": " ".join(domains),
    }
    new_server_env = "".join(f"{k}={shlex.quote(v)}\n" for k, v in server_env.items())
    write_text(SERVER_ENV, new_server_env)
    write_text(HOSTS, "".join(f"{server_ip} {host}\n" for host in hosts))
    dnsmasq = "domain-needed\n"
    if samba:
        # The realm and its SRV records come from the samba DNS
        dnsmasq += f"server=/{samba[1]}/{samba[2]}\n"
    write_text(DNSMASQ_CONF, dnsmasq)

    auth = {"totp_required": is_true(conf["OVPN_TOTP_REQUIRED"])}
    domain = conf["OVPN_USER_DOMAIN"]
    if conf["OVPN_AUTH_MODE"] == "certificate_password" and domain:
        ldap = agent.ldapproxy.Ldapproxy().get_domain(domain)
        if ldap is None:
            log(agent.SD_WARNING + f"user domain {domain} not found: password logins will fail")
        else:
            auth.update({k: ldap[k] for k in ("host", "port", "schema", "base_dn", "bind_dn")})
            write_private(LDAP_PASSWORD, ldap["bind_password"])
    save_json(AUTH_JSON, auth)
    write_disabled(load_json(ACCOUNTS, {}))
    # True when the server must restart to push the new settings
    return new_server_env != old_server_env


def podman_exec(*args, check=True, input=None):
    cmd = ["podman", "exec"] + (["-i"] if input is not None else []) + [CONTAINER, *args]
    proc = subprocess.run(cmd, capture_output=True, text=True, input=input)
    if proc.stderr:
        log(proc.stderr.rstrip())
    if check and proc.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed with exit code {proc.returncode}")
    return proc


def server_running():
    return subprocess.run(["systemctl", "--user", "-q", "is-active", "openvpn-server.service"]).returncode == 0


def pki_list():
    """Return {name: {"status": "valid"|"revoked"|"expired", "expires": "YYMMDDhhmmssZ"}} for the client certificates."""
    states = {"V": "valid", "R": "revoked", "E": "expired"}
    certs = {}
    for line in podman_exec("ovpn-pki", "list").stdout.splitlines():
        name, status, expiry = line.split(" ", 2)
        # A name revoked then issued again keeps one line per certificate: the last one wins
        certs[name] = {"status": states.get(status, status), "expires": expiry}
    return certs


_state_lock = None


def lock_state():
    """Serialize the actions that read then write accounts.json and totp.json.

    The lock lasts until the process exits, so a whole read, change and write sequence
    runs alone. Without it, two tasks at once could each overwrite the other's change.
    """
    global _state_lock
    if _state_lock is None:
        _state_lock = open("state.lock", "w")
        fcntl.flock(_state_lock, fcntl.LOCK_EX)


def load_accounts():
    lock_state()
    return load_json(ACCOUNTS, {})


def save_accounts(accounts):
    save_json(ACCOUNTS, accounts)
    write_disabled(accounts)


def require_enabled_account(name):
    """End the action unless the account exists and is enabled"""
    account = load_accounts().get(name)
    if account is None:
        fail_validation("name", name, "account_not_found")
    if account.get("disabled"):
        fail_validation("name", name, "account_disabled")


def write_disabled(accounts):
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    save_json(DISABLED, sorted(name for name, info in accounts.items() if info.get("disabled")))


def load_totp():
    lock_state()
    return load_json(TOTP_FILE, {})


def save_totp(data):
    save_json(TOTP_FILE, data, private=True)


def totp_ok(secret, code, name=None):
    # The server image owns the TOTP check, so enrollment and login agree on the same rules.
    # With a name the code is spent: the code typed to confirm cannot open a session.
    proc = podman_exec("ovpn-auth", "totp-check", check=False,
                       input=json.dumps({"secret": secret, "code": code, "name": name}))
    return proc.returncode == 0


def fail_validation(field, value, error):
    agent.set_status("validation-failed")
    json.dump([{"field": field, "parameter": field, "value": value, "error": error}], fp=sys.stdout)
    sys.exit(2)


def require_server():
    if not server_running():
        fail_validation("name", "", "server_not_running")


def load_public_key(public_key):
    """Return the RSA key of the browser, or end the action with invalid_public_key.

    Call it before changing any state, so a bad key leaves nothing half done.
    """
    try:
        key = serialization.load_der_public_key(base64.b64decode(public_key))
    except (ValueError, TypeError, UnsupportedAlgorithm):
        fail_validation("public_key", "", "invalid_public_key")
    if not isinstance(key, rsa.RSAPublicKey) or key.key_size < 2048:
        fail_validation("public_key", "", "invalid_public_key")
    return key


def seal(payload, public_key):
    """Encrypt payload for the browser that sent public_key (base64 SPKI, RSA-OAEP SHA-256).

    The core keeps task output in Redis for hours: only ciphertext must land there.
    Without public_key, the payload is returned as is, for api-cli users on the node.
    """
    if not public_key:
        return payload
    key = load_public_key(public_key)
    aes_key = AESGCM.generate_key(bit_length=256)
    iv = os.urandom(12)
    data = AESGCM(aes_key).encrypt(iv, json.dumps(payload).encode(), None)
    wrapped = key.encrypt(aes_key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    return {"sealed": {
        "key": base64.b64encode(wrapped).decode(),
        "iv": base64.b64encode(iv).decode(),
        "data": base64.b64encode(data).decode(),
    }}


def udp_port_in_use(port):
    """True if a socket of the node already listens on this UDP port.

    Modules run on the host network or publish their ports on it, so the kernel tables show them all.
    """
    for table in ("/proc/net/udp", "/proc/net/udp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    local = line.split()[1]
                    if int(local.rsplit(":", 1)[1], 16) == port:
                        return True
        except FileNotFoundError:
            continue
    return False
