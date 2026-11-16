*** Settings ***
Documentation    Password logins against a user domain, authenticator and login history
Resource    roadwarrior.resource

*** Test Cases ***
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
