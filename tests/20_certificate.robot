*** Settings ***
Documentation    VPN client with certificate only: tunnel, firewall, DNS and account life cycle
Resource    roadwarrior.resource

*** Test Cases ***
Check if a certificate account can connect
    Run module action    add-account    {"name": "laptop1"}
    Save profile    laptop1
    ${output} =    Connect client    laptop1    -- ping -c 2 -W 2 10.66.0.1
    Should Contain    ${output}    connected
    Should Contain    ${output}    2 packets received

Check if a client reaches Traefik through the spoke of the hub
    ${output} =    Connect client    laptop1    -- wget -q --no-check-certificate -O /dev/null -S https://10.66.1.2/
    Should Contain    ${output}    HTTP/

Check if SSH is closed to the VPN clients
    ${output} =    Connect client    laptop1    -- sh -c "nc -z -w 3 10.66.1.2 22 && echo SSH_OPEN || echo SSH_CLOSED"
    Should Contain    ${output}    SSH_CLOSED

Check if SSH opens to the VPN clients when the node allows it
    ${since} =    Link of the hub node since
    ${config} =    Configuration    certificate    expose_ssh=true
    Run module action    configure-module    ${config}
    ${output} =    Connect client    laptop1    -- sh -c "nc -z -w 3 10.66.1.2 22 && echo SSH_OPEN || echo SSH_CLOSED"
    Should Contain    ${output}    SSH_OPEN
    ${config} =    Configuration    certificate
    Run module action    configure-module    ${config}
    ${output} =    Connect client    laptop1    -- sh -c "nc -z -w 3 10.66.1.2 22 && echo SSH_OPEN || echo SSH_CLOSED"
    Should Contain    ${output}    SSH_CLOSED
    # A save keeps the certificate of the hub node: its link stays up
    ${after} =    Link of the hub node since
    Should Be Equal    ${since}    ${after}

Check if a hub with accounts cannot become a node
    ${error} =    Validation error of    request-spoke-certificate    {}
    Should Be Equal    ${error}    accounts_exist

Check if the VPN resolver answers the node name
    ${fqdn} =    Execute Command    hostname -f
    ${output} =    Connect client    laptop1    -- nslookup ${fqdn} 10.66.0.1
    Should Contain    ${output}    Address: 10.66.1.2

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
