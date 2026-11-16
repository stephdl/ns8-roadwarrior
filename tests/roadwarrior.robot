*** Settings ***
Library    SSHLibrary
Library    String

*** Variables ***
${ADMIN_USER}       admin
${ADMIN_PASSWORD}    Nethesis,1234
${USER_PASSWORD}    Nethesis,1234
${module_id}        ${EMPTY}
${ldap_id}          ${EMPTY}
${node_ip}          ${EMPTY}
${client_image}     ${EMPTY}
${tun}              ${EMPTY}

*** Keywords ***
Login to cluster-admin
    New Page    https://${NODE_ADDR}/cluster-admin/
    Fill Text    text="Username"    ${ADMIN_USER}
    Click    button >> text="Continue"
    Fill Text    text="Password"    ${ADMIN_PASSWORD}
    Click    button >> text="Log in"
    Wait For Elements State    css=#main-content    visible    timeout=10s

Run module action
    [Arguments]    ${action}    ${data}={}
    ${output}  ${rc} =    Execute Command    api-cli run module/${module_id}/${action} --data '${data}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0    ${action} failed: ${output}
    RETURN    ${output}

Validation error of
    [Arguments]    ${action}    ${data}
    ${output}  ${rc} =    Execute Command    api-cli run module/${module_id}/${action} --data '${data}'
    ...    return_rc=True
    Should Not Be Equal As Integers    ${rc}  0    ${action} should fail
    ${error} =    Execute Command    echo '${output}' | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["error"])'
    RETURN    ${error}

Configuration
    [Arguments]    ${auth_mode}    ${user_domain}=
    RETURN    {"host": "${node_ip}", "port": 11950, "network": "10.66.0.0/24", "auth_mode": "${auth_mode}", "user_domain": "${user_domain}", "totp_required": false, "expose_samba": false}

Save profile
    [Arguments]    ${name}
    ${rc} =    Execute Command    api-cli run module/${module_id}/download-client-config --data '{"name": "${name}"}' | python3 -c 'import json,sys; open("/root/rw-${name}.ovpn","w").write(json.load(sys.stdin)["profile"])'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Connect client
    [Documentation]    ${args} is one shell string: the credentials, then "--" and the command run in the client
    [Arguments]    ${profile}    ${args}=${EMPTY}
    ${output}  ${rc} =    Execute Command    bash /root/vpn-client.sh ${client_image} /root/rw-${profile}.ovpn ${args} 2>&1
    ...    return_rc=True
    RETURN    ${output}

*** Test Cases ***
Check if roadwarrior is installed correctly
    Put File    ${CURDIR}/vpn-client.sh    /root/vpn-client.sh
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${module_id}    ${output.module_id}
    ${ip} =    Execute Command    ip -4 route get 1.1.1.1 | grep -o 'src [0-9.]*' | cut -d' ' -f2
    Set Global Variable    ${node_ip}    ${ip}
    ${image} =    Execute Command    runagent -m ${module_id} printenv ROADWARRIOR_SERVER_IMAGE
    Set Global Variable    ${client_image}    ${image}
    ${name} =    Execute Command    runagent -m ${module_id} printenv OVPN_TUN
    Set Global Variable    ${tun}    ${name}

Check if invalid settings are refused
    ${error} =    Validation error of    configure-module    {"host": "${node_ip}", "port": 11950, "network": "8.8.8.0/24", "auth_mode": "certificate"}
    Should Be Equal    ${error}    network_not_allowed
    ${error} =    Validation error of    configure-module    {"host": "${node_ip}", "port": 11950, "network": "10.66.0.0/24", "auth_mode": "certificate", "totp_required": true}
    Should Be Equal    ${error}    totp_needs_password

Check if roadwarrior can be configured with certificates only
    ${config} =    Configuration    certificate
    Run module action    configure-module    ${config}
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-server openvpn-dns
    Should Be Equal    ${output}    active\nactive
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.0.1/24
    ${rc} =    Execute Command    firewall-cmd --info-service=${module_id} | grep -q 11950/udp
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if a certificate account can connect
    Run module action    add-account    {"name": "laptop1"}
    Save profile    laptop1
    ${output} =    Connect client    laptop1    -- ping -c 2 -W 2 10.66.0.1
    Should Contain    ${output}    connected
    Should Contain    ${output}    2 packets received

Check if a client reaches Traefik through the tunnel
    ${output} =    Connect client    laptop1    -- wget -q --no-check-certificate -O /dev/null -S https://10.66.0.1/
    Should Contain    ${output}    HTTP/

Check if SSH is closed to the VPN clients
    ${output} =    Connect client    laptop1    -- sh -c "nc -z -w 3 10.66.0.1 22 && echo open || echo closed"
    Should Contain    ${output}    closed

Check if the VPN resolver answers the node name
    ${fqdn} =    Execute Command    hostname -f
    ${output} =    Connect client    laptop1    -- nslookup ${fqdn} 10.66.0.1
    Should Contain    ${output}    Address: 10.66.0.1

Check if a disabled account cannot connect
    Run module action    disable-account    {"name": "laptop1"}
    ${output} =    Run module action    list-accounts
    Should Contain    ${output}    "disabled": true
    ${output} =    Connect client    laptop1
    Should Contain    ${output}    refused
    Run module action    enable-account    {"name": "laptop1"}
    ${output} =    Connect client    laptop1
    Should Contain    ${output}    connected

Check if a removed account cannot connect
    Run module action    remove-account    {"name": "laptop1"}
    ${output} =    Connect client    laptop1
    Should Contain    ${output}    refused
    ${output} =    Execute Command    journalctl --since -2min | grep -c 'certificate revoked: CN=laptop1'
    Should Not Be Equal As Strings    ${output}    0

Check if a removed name can be added again
    Run module action    add-account    {"name": "laptop1"}
    Save profile    laptop1
    ${output} =    Connect client    laptop1
    Should Contain    ${output}    connected
    Run module action    remove-account    {"name": "laptop1"}

Check if roadwarrior can check domain passwords
    # openldap is a core module, out of the Software Center list: take its last stable image from the repository
    ${image} =    Execute Command    redis-cli --raw hget cluster/repository_cache/default data | python3 -c 'import json,sys; m=[m for m in json.load(sys.stdin) if m["id"] == "openldap"][0]; print(m["source"] + ":" + [v["tag"] for v in m["versions"] if not v["testing"]][0])'
    ${output}  ${rc} =    Execute Command    add-module ${image} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${ldap_id}    ${output.module_id}
    ${rc} =    Execute Command    api-cli run module/${ldap_id}/configure-module --data '{"provision": "new-domain", "domain": "rwci.test", "admuser": "admin", "admpass": "${USER_PASSWORD}"}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${rc} =    Execute Command    api-cli run module/${ldap_id}/add-user --data '{"user": "rwci", "display_name": "RW CI", "password": "${USER_PASSWORD}", "locked": false, "groups": []}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${config} =    Configuration    certificate_password    rwci.test
    Run module action    configure-module    ${config}
    Run module action    add-account    {"name": "rwci"}
    Save profile    rwci
    ${output} =    Execute Command    grep -c '^auth-user-pass' /root/rw-rwci.ovpn
    Should Be Equal    ${output}    1

Check if the right password connects
    ${output} =    Connect client    rwci    rwci '${USER_PASSWORD}'
    Should Contain    ${output}    connected

Check if a wrong password is refused
    ${output} =    Connect client    rwci    rwci wrong-password
    Should Contain    ${output}    refused

Check if an account is locked while it exists
    ${config} =    Configuration    certificate
    ${error} =    Validation error of    configure-module    ${config}
    Should Be Equal    ${error}    auth_mode_locked

Check if the authenticator can be set up
    ${output} =    Run module action    enroll-totp    {"name": "rwci"}
    ${secret} =    Execute Command    echo '${output}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])'
    ${code} =    Execute Command    python3 -c 'import base64,hashlib,hmac,struct,time; k=base64.b32decode("${secret}" + "=" * (-len("${secret}") % 8)); d=hmac.new(k, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest(); o=d[-1] & 15; print("%06d" % ((struct.unpack(">I", d[o:o+4])[0] & 0x7FFFFFFF) % 1000000))'
    ${error} =    Validation error of    confirm-totp    {"name": "rwci", "code": "000000"}
    Should Be Equal    ${error}    wrong_code
    Run module action    confirm-totp    {"name": "rwci", "code": "${code}"}
    ${output} =    Run module action    list-accounts
    Should Contain    ${output}    "totp_enrolled": true

Check if the login history records the attempts
    ${output} =    Run module action    get-login-history    {"name": "rwci"}
    Should Contain    ${output}    "event": "login"
    Should Contain    ${output}    "reason": "wrong_password"

Take screenshots
    [Tags]    ui
    Import Library    Browser
    New Browser    chromium    headless=True
    New Context    ignoreHTTPSErrors=True
    Login to cluster-admin
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}
    Wait For Elements State    iframe >>> h2 >> text="Status"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/1._Status.png
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=accounts
    Wait For Elements State    iframe >>> h2 >> text="Accounts"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/2._Accounts.png
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=settings
    Wait For Elements State    iframe >>> h2 >> text="Settings"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/3._Settings.png
    Close Browser

Check if roadwarrior is removed correctly
    Execute Command    rm -f /root/vpn-client.sh /root/rw-*.ovpn
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${rc} =    Execute Command    ip link show ${tun}
    ...    return_rc=True  return_stdout=False
    Should Not Be Equal As Integers    ${rc}  0
    ${output} =    Execute Command    firewall-cmd --get-zones
    Should Not Contain    ${output}    ${tun}
    ${rc} =    Execute Command    remove-module --no-preserve ${ldap_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
