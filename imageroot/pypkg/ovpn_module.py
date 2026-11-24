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
import time
from datetime import datetime, timezone

import agent
from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import agent.ldapproxy

CONTAINER = "openvpn-server"
S2S_CONTAINER = "openvpn-s2s"
RUNTIME_DIR = "ovpn"
SERVER_ENV = "ovpn/server.env"
S2S_ENV = "ovpn/s2s.env"
SPOKE_ENV = "ovpn/spoke.env"
CCD_DIR = "ovpn/ccd"
SPOKE_CA = "ovpn/spoke-ca.crt"
SPOKE_CERT = "ovpn/spoke.crt"
SPOKE_KEY = "secrets/spoke.key"
# What the hub gave this node when it joined: {"hub", "hub_uuid", "ip", "rw_network", "ca", "cert"}
SPOKE_JOIN = "spoke.json"
# Nodes registered on a hub: {module_uuid: {"module_id", "node_id", "ip", "expose_samba"}}.
# The uuid is the key: a restore in place changes the module id, never the uuid.
SPOKES = "spokes.json"
# Names of the tun devices inside the network namespace of the hub pod
HUB_RW_TUN = "tunrw"
HUB_S2S_TUN = "tuns2s"
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
    "OVPN_MODE": "hub",
    "OVPN_HUB": "",
}

MODES = ("hub", "spoke")
# Units of each mode. A hub also runs a spoke, so the apps of its own node are reached like the others.
UNITS = {
    "hub": ["openvpn-hub.service", "openvpn-hub-server.service", "openvpn-hub-dns.service",
            "openvpn-s2s.service", "openvpn-spoke.service"],
    "spoke": ["openvpn-spoke.service"],
}
ALL_UNITS = sorted({unit for units in UNITS.values() for unit in units})
SERVER_UNIT = "openvpn-hub-server.service"
DNS_UNIT = "openvpn-hub-dns.service"

# Ports of samba, from ns8-samba create-module/70firewall
SAMBA_PORTS = [
    "53/tcp", "53/udp", "88/tcp", "88/udp", "135/tcp", "137/udp", "138/udp", "139/tcp",
    "389/tcp", "389/udp", "445/tcp", "464/tcp", "464/udp", "636/tcp", "3268/tcp", "3269/tcp",
    "49152-65535/tcp", "123/udp",
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
    return bool(os.environ.get("OVPN_HOST")) or mode() == "spoke"


def mode():
    return os.environ.get("OVPN_MODE") or "hub"


def s2s_networks(rw_cidr):
    """Addresses of the site-to-site link of a hub, next to the network of the users.

    The link takes the other half of the supernet of the users network. A node tun gets the
    supernet prefix, so its replies to the users go back into the tunnel with no extra route.
    """
    rw = ipaddress.ip_network(rw_cidr, strict=True)
    supernet = rw.supernet()
    s2s = next(net for net in supernet.subnets(new_prefix=rw.prefixlen) if net != rw)
    hosts = s2s.hosts()
    hub_ip = str(next(hosts))
    local_ip = str(next(hosts))
    return {"supernet": supernet, "s2s": s2s, "hub_ip": hub_ip, "local_ip": local_ip}


def host_tun_ip(conf=None):
    """Address of the tun the core creates on the node, with its prefix."""
    conf = conf or settings()
    if mode() == "spoke":
        return os.environ.get("OVPN_SPOKE_IP", "")
    link = s2s_networks(conf["OVPN_NETWORK"])
    return f"{link['local_ip']}/{link['supernet'].prefixlen}"


def users_network():
    """Network of the users, as the node tun sees them: the one of the hub on a spoke."""
    if mode() == "spoke":
        return os.environ.get("OVPN_RW_NETWORK", "")
    return settings()["OVPN_NETWORK"]


def node_vpn_ip(rdb, node_id):
    return rdb.hget(f"node/{node_id}/vpn", "ip_address") or ""


def list_hubs(rdb):
    """Hubs of the cluster a node can join: [{"module_id", "module_uuid", "node_id", "node_name", "host", "leader"}]."""
    hubs = []
    leader_id = rdb.hget("cluster/environment", "NODE_ID") or ""
    for key in rdb.scan_iter("module/roadwarrior*/environment"):
        env = rdb.hgetall(key)
        module_id = key.split("/")[1]
        if env.get("OVPN_MODE") == "hub" and module_id != os.environ.get("MODULE_ID"):
            hubs.append({"module_id": module_id, "module_uuid": env.get("MODULE_UUID", ""),
                         "node_id": env.get("NODE_ID", ""), "host": env.get("OVPN_HOST", ""),
                         "node_name": rdb.get(f"node/{env.get('NODE_ID')}/ui_name") or "",
                         "leader": env.get("NODE_ID") == leader_id})
    return sorted(hubs, key=lambda h: h["module_id"])


def roadwarrior_instances(rdb):
    """Current {module_uuid: (module_id, node_id)} of the roadwarrior instances of the cluster."""
    instances = {}
    for key in rdb.scan_iter("module/roadwarrior*/environment"):
        uuid, node_id = rdb.hmget(key, "MODULE_UUID", "NODE_ID")
        if uuid:
            instances[uuid] = (key.split("/")[1], node_id or "")
    return instances


def current_spokes(rdb):
    """Registered nodes with their current module id and node: a restore or a move changes them."""
    spokes = load_json(SPOKES, {})
    instances = roadwarrior_instances(rdb)
    for uuid, info in spokes.items():
        if uuid in instances:
            info["module_id"], info["node_id"] = instances[uuid]
    return spokes


def current_hub(rdb):
    """Module id of the hub this node joined, found again by its uuid after a restore of the hub."""
    hub_uuid = load_join().get("hub_uuid", "")
    return roadwarrior_instances(rdb).get(hub_uuid, (os.environ.get("OVPN_HUB", ""), ""))[0]


def load_spokes():
    lock_state()
    return load_json(SPOKES, {})


def save_spokes(spokes):
    lock_state()
    save_json(SPOKES, spokes)


def assign_spoke_ip(spokes, uuid, conf=None):
    """Keep the address of a node that joins again, else take the first free one."""
    conf = conf or settings()
    if uuid in spokes:
        return spokes[uuid]["ip"]
    link = s2s_networks(conf["OVPN_NETWORK"])
    if uuid == os.environ["MODULE_UUID"]:
        return link["local_ip"]
    taken = {link["hub_ip"], link["local_ip"]} | {info["ip"] for info in spokes.values()}
    for host in link["s2s"].hosts():
        if str(host) not in taken:
            return str(host)
    raise RuntimeError("no free address left in the site-to-site network")


def sign_spoke(name, csr):
    """Sign the CSR of a node with the site-to-site CA. Return (ca, cert)."""
    # The server container creates the PKI when it starts: give it some time after a restart
    for _ in range(30):
        proc = podman_exec("ovpn-pki", "s2s-sign", name, input=csr, container=S2S_CONTAINER, check=False)
        if proc.returncode == 0:
            break
        time.sleep(2)
    else:
        raise RuntimeError(f"cannot sign the certificate of {name}")
    cert = proc.stdout
    ca = podman_exec("ovpn-pki", "s2s-ca", container=S2S_CONTAINER).stdout
    return ca, cert


def register_spoke(module_id, uuid, node_id, csr, expose_samba):
    """Register a node on this hub and return what it needs to join, to pass to its configure-module."""
    conf = settings()
    spokes = load_spokes()
    if uuid == os.environ["MODULE_UUID"]:
        # A cloned hub has a new uuid: its own spoke under the old one goes
        local_ip = s2s_networks(conf["OVPN_NETWORK"])["local_ip"]
        spokes = {k: v for k, v in spokes.items() if k == uuid or v["ip"] != local_ip}
    ip = assign_spoke_ip(spokes, uuid, conf)
    ca, cert = sign_spoke(uuid, csr)
    spokes[uuid] = {"module_id": module_id, "node_id": str(node_id), "ip": ip, "expose_samba": bool(expose_samba)}
    save_spokes(spokes)
    link = s2s_networks(conf["OVPN_NETWORK"])
    return {
        "hub": os.environ["MODULE_ID"],
        "hub_uuid": os.environ["MODULE_UUID"],
        "ip": f"{ip}/{link['supernet'].prefixlen}",
        "rw_network": conf["OVPN_NETWORK"],
        "ca": ca,
        "cert": cert,
    }


def unregister_spoke(rdb, module_id):
    """Remove a node by its current module id, or by the last one known when it is gone."""
    spokes = load_spokes()
    current = current_spokes(rdb)
    uuid = next((u for u, info in current.items() if info["module_id"] == module_id), None)
    if uuid is None:
        return False
    spokes.pop(uuid)
    podman_exec("ovpn-pki", "s2s-revoke", uuid, container=S2S_CONTAINER, check=False)
    save_spokes(spokes)
    return True


def spoke_key_and_csr():
    """Key of the node for the site-to-site link, made once. Only the CSR leaves the node."""
    from cryptography import x509
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    try:
        with open(SPOKE_KEY, "rb") as f:
            key = serialization.load_pem_private_key(f.read(), password=None)
    except FileNotFoundError:
        key = ec.generate_private_key(ec.SECP384R1())
        write_private(SPOKE_KEY, key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption()).decode())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, os.environ["MODULE_UUID"])])
    csr = x509.CertificateSigningRequestBuilder().subject_name(name).sign(key, hashes.SHA256())
    return csr.public_bytes(serialization.Encoding.PEM).decode()


def load_join():
    return load_json(SPOKE_JOIN, {})


def save_join(join):
    """Keep what the hub gave. It is in the backup: a restored node joins again without the hub."""
    save_json(SPOKE_JOIN, join)


def save_spoke_certs(ca, cert):
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    changed = write_if_changed(SPOKE_CA, ca)
    return write_if_changed(SPOKE_CERT, cert) or changed


def spoke_hub_endpoint(rdb):
    """Address and port of the hub, read again at each start: the hub may move to another node."""
    if mode() == "hub":
        node_id = os.environ["NODE_ID"]
        port = os.environ.get("OVPN_S2S_PORT", "")
    else:
        hub = current_hub(rdb)
        node_id = rdb.hget("cluster/module_node", hub) or ""
        port = rdb.hget(f"module/{hub}/environment", "OVPN_S2S_PORT") or ""
    return node_vpn_ip(rdb, node_id), port


def write_if_changed(path, text):
    try:
        with open(path) as f:
            if f.read() == text:
                return False
    except FileNotFoundError:
        pass
    write_text(path, text)
    return True


def env_text(values):
    return "".join(f"{k}={shlex.quote(v)}\n" for k, v in values.items())


def samba_on_node(rdb, node_id):
    """Return (module_id, realm, ip) of the samba DC of this node, or None."""
    for key in rdb.scan_iter("module/*/environment"):
        module_id = key.split("/")[1]
        env = rdb.hgetall(key)
        # Some samba releases drop the account_provider flag: the DC still publishes its ldap service
        is_dc = "account_provider" in rdb.smembers(f"module/{module_id}/flags") \
            or rdb.hget(f"module/{module_id}/srv/tcp/ldap", "schema") == "ad"
        if env.get("NODE_ID") == str(node_id) and env.get("REALM") and env.get("IPADDRESS") and is_dc:
            return module_id, env["REALM"].lower(), env["IPADDRESS"]
    return None


def is_route_of(instance, module_id):
    """Traefik names the routes of a module after it: the module id, or the module id and a suffix."""
    return bool(module_id) and (instance == module_id or instance.startswith(module_id + "_"))


def traefik_hosts(rdb, node_id, skip_module=""):
    traefik = rdb.get(f"node/{node_id}/default_instance/traefik")
    if not traefik:
        return []
    # The hosts set keeps the name of a route moved to another node: ask Traefik for its real routes
    response = agent.tasks.run(agent_id=f"module/{traefik}", action="list-routes", data={"expand_list": True},
                               extra={"isNotificationHidden": True})
    if response["exit_code"] == 0 and isinstance(response["output"], list):
        return sorted({route["host"] for route in response["output"]
                       if route.get("host") and not is_route_of(route.get("instance", ""), skip_module)})
    log(agent.SD_WARNING + f"cannot list the routes of {traefik}, using its hosts set: {response.get('error', '')}")
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


def write_runtime(rdb=None, skip_module=""):
    """Write the files read by the containers of the mode.

    skip_module is a module just removed: Traefik may still list its routes for a moment.
    Return the set of units that must restart to apply the change.
    """
    # disabled.json comes from accounts.json: read and write them under the same lock as the actions
    lock_state()
    rdb = rdb or agent.redis_connect(use_replica=True)
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    changed = set()
    if mode() == "spoke":
        join = load_join()
        if join and save_spoke_certs(join["ca"], join["cert"]):
            changed.add("openvpn-spoke.service")
    remote, port = spoke_hub_endpoint(rdb)
    if write_if_changed(SPOKE_ENV, env_text({
        "OVPN_TUN": os.environ["OVPN_TUN"],
        "SPOKE_REMOTE": remote,
        "SPOKE_PORT": port,
    })):
        changed.add("openvpn-spoke.service")
    if mode() == "hub":
        changed |= write_server_runtime(rdb, skip_module)
    return changed


def node_names(rdb, node_id, vpn_host, skip_module=""):
    """Names of the HTTP routes of a node. The VPN host stays out, or a reconnect would look for it in the tunnel."""
    return {h.lower() for h in traefik_hosts(rdb, node_id, skip_module) if "." in h} - {vpn_host}


def write_server_runtime(rdb, skip_module=""):
    """Files of the user server, of the resolver and of the site-to-site server."""
    conf = settings()
    net, server_ip = network_parts(conf["OVPN_NETWORK"])
    vpn_host = conf["OVPN_HOST"].lower()
    link = s2s_networks(conf["OVPN_NETWORK"])
    spokes = current_spokes(rdb)
    # The node name serves cluster-admin and path routes: it must enter the tunnel too
    own_names = node_names(rdb, os.environ["NODE_ID"], vpn_host, skip_module) | ({socket.getfqdn().lower()} - {vpn_host} if "." in socket.getfqdn() else set())
    # Each name answers with the address of the node that serves it, the hub node first
    addresses = {host: link["local_ip"] for host in own_names}
    dcs_by_spoke = {}
    for spoke_id, info in sorted(spokes.items()):
        if spoke_id != os.environ["MODULE_UUID"]:
            for host in node_names(rdb, info["node_id"], vpn_host, skip_module):
                addresses.setdefault(host, info["ip"])
        expose = is_true(conf["OVPN_EXPOSE_SAMBA"]) if spoke_id == os.environ["MODULE_UUID"] else info.get("expose_samba")
        samba = samba_on_node(rdb, info["node_id"]) if expose else None
        if samba:
            dcs_by_spoke[spoke_id] = samba
    dcs = list(dcs_by_spoke.values())
    changed = write_s2s_runtime(link, spokes, dcs_by_spoke)

    hosts = sorted(addresses)
    domains = vpn_domains(hosts, vpn_host)
    push_routes = [f"{link['s2s'].network_address}/{link['s2s'].netmask}"]
    for _, realm, ip in dcs:
        push_routes.append(f"{ip}/255.255.255.255")
        domains.add(realm)
    domains = sorted(domains)

    server_env = {
        "OVPN_TUN": HUB_RW_TUN,
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
    if write_if_changed(SERVER_ENV, env_text(server_env)):
        changed.add(SERVER_UNIT)
    write_text(HOSTS, "".join(f"{addresses[host]} {host}\n" for host in hosts))
    dnsmasq = "domain-needed\n"
    for _, realm, ip in dcs:
        # The realm and its SRV records come from the samba DNS
        dnsmasq += f"server=/{realm}/{ip}\n"
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
    return changed


def write_s2s_runtime(link, spokes, dcs_by_spoke):
    """Settings of the site-to-site server and one ccd file per node, with its fixed address."""
    os.makedirs(CCD_DIR, exist_ok=True)
    wanted = {}
    for spoke_id, info in spokes.items():
        ccd = f"ifconfig-push {info['ip']} {link['s2s'].netmask}\n"
        if spoke_id in dcs_by_spoke:
            # The DC of this node answers on its own address: the hub routes it into this node
            ccd += f"iroute {dcs_by_spoke[spoke_id][2]} 255.255.255.255\n"
        wanted[spoke_id] = ccd
    for name in os.listdir(CCD_DIR):
        if name not in wanted:
            os.unlink(os.path.join(CCD_DIR, name))
    for name, text in wanted.items():
        write_if_changed(os.path.join(CCD_DIR, name), text)
    s2s_env = {
        "RW_TUN": HUB_RW_TUN,
        "S2S_TUN": HUB_S2S_TUN,
        "S2S_NETWORK": str(link["s2s"].network_address),
        "S2S_NETMASK": str(link["s2s"].netmask),
        "S2S_PORT": os.environ.get("OVPN_S2S_PORT", ""),
        "S2S_ROUTES": " ".join(f"{dc[2]}/255.255.255.255" for dc in dcs_by_spoke.values()),
    }
    return {"openvpn-s2s.service"} if write_if_changed(S2S_ENV, env_text(s2s_env)) else set()


def apply_runtime(changed):
    """Restart what must restart, and let the resolver read its lists again."""
    # A unit writes the runtime files before it starts: it would wait for our lock forever
    unlock_state()
    for unit in sorted(changed):
        subprocess.run(["systemctl", "--user", "try-restart", unit], check=False)
    if mode() == "hub":
        subprocess.run(["systemctl", "--user", "reload", DNS_UNIT], check=False)


def podman_exec(*args, check=True, input=None, container=CONTAINER):
    cmd = ["podman", "exec"] + (["-i"] if input is not None else []) + [container, *args]
    proc = subprocess.run(cmd, capture_output=True, text=True, input=input)
    if proc.stderr:
        log(proc.stderr.rstrip())
    if check and proc.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed with exit code {proc.returncode}")
    return proc


def server_running():
    return subprocess.run(["systemctl", "--user", "-q", "is-active", SERVER_UNIT]).returncode == 0


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


def unlock_state():
    global _state_lock
    if _state_lock is not None:
        _state_lock.close()
        _state_lock = None


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
