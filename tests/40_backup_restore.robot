*** Settings ***
Documentation    Backup and in place restore keep the PKI and the accounts
Resource    roadwarrior.resource

*** Test Cases ***
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
