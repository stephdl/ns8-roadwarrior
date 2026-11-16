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
    ${output} =    Execute Command    runagent -m ${module_id} systemctl --user is-active openvpn-server openvpn-dns
    Should Be Equal    ${output}    active\nactive
    ${output} =    Execute Command    ip -4 -o addr show ${tun}
    Should Contain    ${output}    10.66.0.1/24
    ${rc} =    Execute Command    firewall-cmd --info-service=${module_id} | grep -q 11950/udp
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
