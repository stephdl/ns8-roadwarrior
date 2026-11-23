*** Settings ***
Documentation    A hub reaches the apps of its own node through its spoke, like those of another node
Resource    roadwarrior.resource

*** Test Cases ***
Check if roadwarrior can run as a hub
    Run module action    configure-module    {"mode": "hub", "host": "${node_ip}", "port": 11950, "network": "10.66.0.0/24", "auth_mode": "certificate", "expose_samba": false}
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-hub openvpn-hub-server openvpn-hub-dns openvpn-s2s openvpn-spoke
    Should Be Equal    ${output}    active\nactive\nactive\nactive\nactive
    # The node tun is the spoke of the hub: its prefix covers the users network
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.1.2/23

Check if the spoke of the hub joined the link
    ${output} =    Execute Command    api-cli run module/${module_id}/list-spokes
    ${spokes} =    Evaluate    json.loads($output)    modules=json
    Should Be Equal    ${spokes}[0][module_id]    ${module_id}
    Should Be Equal    ${spokes}[0][ip]    10.66.1.2
    Wait Until Keyword Succeeds    30s    3s    Spoke is connected

Check if a client reaches the node through the hub
    Run module action    add-account    {"name": "hubuser"}
    Save profile    hubuser
    # Traefik answers on the spoke address: the client went through the hub and the link
    ${output} =    Connect client    hubuser    -- sh -c 'wget -q -S -O /dev/null http://10.66.1.2/ 2>&1 | head -1; true'
    Should Contain    ${output}    connected
    Should Contain    ${output}    HTTP/

Check if the hub refuses another caller
    ${output}    ${rc} =    Execute Command    api-cli run module/${module_id}/add-spoke --data '{"csr": "-----BEGIN CERTIFICATE REQUEST-----"}'
    ...    return_rc=True
    Should Not Be Equal As Integers    ${rc}    0

Check if roadwarrior goes back to standalone
    Run module action    remove-account    {"name": "hubuser"}
    ${config} =    Configuration    certificate
    Run module action    configure-module    ${config}
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-server openvpn-hub
    Should Be Equal    ${output}    active\ninactive
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.0.1/24

*** Keywords ***
Spoke is connected
    ${output} =    Execute Command    api-cli run module/${module_id}/list-spokes
    ${spokes} =    Evaluate    json.loads($output)    modules=json
    Should Be True    ${spokes}[0][connected]
