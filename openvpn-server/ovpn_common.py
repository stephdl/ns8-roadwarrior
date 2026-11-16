#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Helpers shared by the OpenVPN hooks of the server image

import json

DISABLED = "/run/ovpn/disabled.json"


def is_disabled(name):
    """True if the module lists the account as disabled. Names compare without case, like logins."""
    try:
        with open(DISABLED) as f:
            return name.lower() in {n.lower() for n in json.load(f)}
    except (FileNotFoundError, ValueError):
        return False
