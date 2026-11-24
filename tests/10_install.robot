*** Settings ***
Documentation    Install and configure the module
Resource    roadwarrior.resource

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
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-hub openvpn-hub-server openvpn-hub-dns openvpn-s2s openvpn-spoke
    Should Be Equal    ${output}    active\nactive\nactive\nactive\nactive
    # The node tun is the spoke of the hub: its prefix covers the users network
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.1.2/23
    ${rc} =    Execute Command    firewall-cmd --info-service=${module_id} | grep -q 11950/udp
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if the spoke of the hub joined the link
    ${spokes} =    Run module action    list-spokes
    ${spokes} =    Evaluate    json.loads($spokes)    modules=json
    Should Be Equal    ${spokes}[0][module_id]    ${module_id}
    Should Be Equal    ${spokes}[0][ip]    10.66.1.2
    Wait Until Keyword Succeeds    60s    3s    Spoke is connected

Check if the hub reaches the node through the link
    ${output} =    Execute Command    runagent -m ${module_id} podman exec openvpn-server wget -q -S -O /dev/null http://10.66.1.2/ 2>&1 | head -1
    Should Contain    ${output}    HTTP/
    ${output} =    Execute Command    runagent -m ${module_id} podman exec openvpn-s2s nft list chain inet roadwarrior forward
    Should Contain    ${output}    iifname "tunrw" oifname "tuns2s" accept

Check if the hub refuses an unknown node
    ${error} =    Validation error of    add-spoke    {"module_id": "roadwarrior999", "csr": "-----BEGIN CERTIFICATE REQUEST-----"}
    Should Be Equal    ${error}    module_not_found

*** Keywords ***
Spoke is connected
    ${spokes} =    Run module action    list-spokes
    ${spokes} =    Evaluate    json.loads($spokes)    modules=json
    Should Be True    ${spokes}[0][connected]
