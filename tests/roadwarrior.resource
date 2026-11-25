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
    [Arguments]    ${auth_mode}    ${user_domain}=    ${expose_ssh}=false
    RETURN    {"host": "${node_ip}", "port": 11950, "network": "10.66.0.0/24", "auth_mode": "${auth_mode}", "user_domain": "${user_domain}", "totp_required": false, "expose_samba": false, "expose_ssh": ${expose_ssh}}

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
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-hub-server
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

Link of the hub node since
    ${spokes} =    Run module action    list-spokes
    ${spokes} =    Evaluate    json.loads($spokes)    modules=json
    Should Be True    ${spokes}[0][connected]
    RETURN    ${spokes}[0][connected_since]
