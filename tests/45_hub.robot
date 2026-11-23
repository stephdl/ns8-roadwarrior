*** Settings ***
Documentation    A hub reaches the apps of its own node through its spoke, like those of another node
Resource    roadwarrior.resource

*** Test Cases ***
Check if roadwarrior can run as a hub
    # The account of the password suite exists: host, port, network and auth mode stay
    Run module action    configure-module    {"mode": "hub", "host": "${node_ip}", "port": 11950, "network": "10.66.0.0/24", "auth_mode": "certificate_password", "user_domain": "rwci.test", "expose_samba": false}
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-hub openvpn-hub-server openvpn-hub-dns openvpn-s2s openvpn-spoke
    Should Be Equal    ${output}    active\nactive\nactive\nactive\nactive
    # The node tun is the spoke of the hub: its prefix covers the users network
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.1.2/23

Check if the spoke of the hub joined the link
    ${spokes} =    Run module action    list-spokes
    ${spokes} =    Evaluate    json.loads($spokes)    modules=json
    Should Be Equal    ${spokes}[0][module_id]    ${module_id}
    Should Be Equal    ${spokes}[0][ip]    10.66.1.2
    Wait Until Keyword Succeeds    60s    3s    Spoke is connected

Check if the hub reaches the node through the link
    # The account of the password suite has an authenticator: test the link from the hub pod
    ${output} =    Execute Command    runagent -m ${module_id} podman exec openvpn-server wget -q -S -O /dev/null http://10.66.1.2/ 2>&1 | head -1
    Should Contain    ${output}    HTTP/
    ${output} =    Execute Command    runagent -m ${module_id} podman exec openvpn-s2s nft list chain inet roadwarrior forward
    Should Contain    ${output}    iifname "tunrw" oifname "tuns2s" accept

Check if the hub refuses an unknown node
    ${error} =    Validation error of    add-spoke    {"module_id": "roadwarrior999", "csr": "-----BEGIN CERTIFICATE REQUEST-----"}
    Should Be Equal    ${error}    module_not_found

Check if roadwarrior goes back to standalone
    ${config} =    Configuration    certificate_password    rwci.test
    Run module action    configure-module    ${config}
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-server openvpn-hub
    Should Be Equal    ${output}    active\ninactive
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.0.1/24

*** Keywords ***
Spoke is connected
    ${spokes} =    Run module action    list-spokes
    ${spokes} =    Evaluate    json.loads($spokes)    modules=json
    Should Be True    ${spokes}[0][connected]
