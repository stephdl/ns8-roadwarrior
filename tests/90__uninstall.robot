*** Settings ***
Documentation    Remove the module and the test user domain
Resource    roadwarrior.resource

*** Test Cases ***
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
