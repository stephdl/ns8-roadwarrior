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

Run task
    [Arguments]    ${action}    ${input}
    ${stdout}    ${stderr}    ${rc} =    Execute Command    api-cli run ${action} --data '${input}'
    ...    return_stdout=True    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    ${action} failed: ${stderr}
    IF    len($stdout) > 0
        ${response} =    Evaluate    json.loads($stdout)    modules=json
    ELSE
        ${response} =    Set Variable    ${stdout}
    END
    RETURN    ${response}

Fingerprint
    [Documentation]    SHA-256 fingerprint of a certificate in the PKI of the module
    [Arguments]    ${file}
    ${output} =    Execute Command    runagent -m ${module_id} podman exec openvpn-server openssl x509 -in /etc/openvpn/pki/${file} -noout -fingerprint -sha256
    Should Contain    ${output}    Fingerprint
    RETURN    ${output}

Server is running
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-server
    Should Be Equal    ${output}    active

Module environment
    [Arguments]    ${name}
    ${output} =    Execute Command    runagent -m ${module_id} printenv ${name}
    RETURN    ${output.strip()}

Client is connected
    ${output} =    Execute Command    podman logs rw-client 2>&1 | grep -c 'Initialization Sequence Completed'
    Should Not Be Equal As Strings    ${output}    0

Client stopped on halt
    ${output} =    Execute Command    podman logs rw-client 2>&1 | grep -c server-pushed-halt; podman rm -f rw-client >/dev/null 2>&1
    Should Be Equal As Strings    ${output}    1

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

Check if a renewed certificate replaces the old profile
    Execute Command    cp /root/rw-laptop1.ovpn /root/rw-laptop1-old.ovpn
    Run module action    renew-account    {"name": "laptop1"}
    Save profile    laptop1
    ${output} =    Connect client    laptop1
    Should Contain    ${output}    connected
    ${output} =    Connect client    laptop1-old
    Should Contain    ${output}    refused

Check if a disconnect stops the client
    # The client stays up in the background, the kill must make it exit instead of reconnecting
    Execute Command    RW_KEEP_CLIENT=1 nohup bash /root/vpn-client.sh ${client_image} /root/rw-laptop1.ovpn -- sleep 90 >/dev/null 2>&1 &
    Wait Until Keyword Succeeds    40 seconds    2 seconds    Client is connected
    Run module action    kill-session    {"name": "laptop1"}
    Wait Until Keyword Succeeds    30 seconds    2 seconds    Client stopped on halt

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

Record the PKI before the backup
    ${ca} =    Fingerprint    ca.crt
    ${cert} =    Fingerprint    issued/rwci.crt
    ${accounts} =    Run module action    list-accounts
    ${uuid} =    Module environment    MODULE_UUID
    ${node} =    Module environment    NODE_ID
    Set Suite Variable    ${ca_sum}    ${ca}
    Set Suite Variable    ${cert_sum}    ${cert}
    Set Suite Variable    ${accounts_before}    ${accounts}
    Set Suite Variable    ${module_uuid}    ${uuid}
    Set Suite Variable    ${module_node}    ${node}
    Set Suite Variable    ${old_module_id}    ${module_id}

Back up roadwarrior
    # A repository URL must be unique: reuse the one of the node if it exists
    ${ip} =    Execute Command    redis-cli hget node/${module_node}/vpn ip_address
    ${url} =    Set Variable    webdav:http://${ip.strip()}:4694
    ${repos} =    Run task    cluster/list-backup-repositories    {}
    ${found} =    Evaluate    [r['id'] for r in $repos['repositories'] if r['url'] == $url]
    IF    ${found}
        Set Suite Variable    ${repository}    ${found}[0]
        Set Suite Variable    ${repository_created}    ${FALSE}
    ELSE
        ${out} =    Run task    cluster/add-backup-repository
        ...    {"provider":"cluster","name":"roadwarrior-test","url":"${url}","password":"","parameters":{}}
        Set Suite Variable    ${repository}    ${out}[id]
        Set Suite Variable    ${repository_created}    ${TRUE}
    END
    # run-backup skips a disabled backup: enable it on a far schedule
    ${bid} =    Run task    cluster/add-backup
    ...    {"name":"roadwarrior-test","instances":["${module_id}"],"repository":"${repository}","schedule":"*-12-31 03:17:00","retention":1,"enabled":true}
    Set Suite Variable    ${backup_id}    ${bid}
    Run task    cluster/run-backup    {"id":${backup_id}}
    ${snapshots} =    Run task    cluster/read-backup-snapshots
    ...    {"repository":"${repository}","path":"roadwarrior/${module_uuid}"}
    Should Not Be Empty    ${snapshots}
    Set Suite Variable    ${snapshot}    ${snapshots}[-1][id]

Restore roadwarrior in place
    ${out} =    Run task    cluster/restore-module
    ...    {"repository":"${repository}","path":"roadwarrior/${module_uuid}","snapshot":"${snapshot}","node":${module_node},"replace":true}
    Should Be Equal    ${out}[module_uuid]    ${module_uuid}
    Should Not Be Equal    ${out}[module_id]    ${old_module_id}
    Set Global Variable    ${module_id}    ${out}[module_id]
    ${name} =    Module environment    OVPN_TUN
    Set Global Variable    ${tun}    ${name}
    ${rc} =    Execute Command    runagent -m ${old_module_id} true
    ...    return_rc=True    return_stdout=False
    Should Not Be Equal As Integers    ${rc}    0    ${old_module_id} must be gone after a replace

Check if the restore keeps the CA, the certificates and the accounts
    # The copy starts once the replaced instance is gone, through the module-removed event
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Server is running
    ${ca} =    Fingerprint    ca.crt
    Should Be Equal    ${ca}    ${ca_sum}
    ${cert} =    Fingerprint    issued/rwci.crt
    Should Be Equal    ${cert}    ${cert_sum}
    ${accounts} =    Run module action    list-accounts
    Should Contain    ${accounts}    "name": "rwci"
    Should Contain    ${accounts}    "totp_enrolled": true

Check if a profile made before the backup still connects
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Server is running
    # The account has an authenticator: the client gets the code challenge, which proves
    # the server accepted the old certificate and the password
    ${output} =    Connect client    rwci    rwci '${USER_PASSWORD}'
    Should Contain    ${output}    CRV1

Remove the test backup
    Run task    cluster/remove-backup    {"id":${backup_id}}
    IF    ${repository_created}
        Run task    cluster/remove-backup-repository    {"id":"${repository}"}
    END

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
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=sessions
    Wait For Elements State    iframe >>> h2 >> text="Sessions"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/3._Sessions.png
    Go To    https://${NODE_ADDR}/cluster-admin/#/apps/${module_id}?page=settings
    Wait For Elements State    iframe >>> h2 >> text="Settings"    visible    timeout=10s
    Sleep    5s
    Take Screenshot    filename=${OUTPUT DIR}/browser/screenshot/4._Settings.png
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
