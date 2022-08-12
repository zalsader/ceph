#!/bin/bash

source $CEPH_PATH/src/daos/require_variables.sh
source $CEPH_PATH/src/daos/daos/initialize_daos_bin.sh

function get_daos_system_error()
{
    require_variables DAOS_BIN COMMAND_PREFIX
    $COMMAND_PREFIX ${DAOS_BIN}/dmg system query --json > /tmp/daos_system_error.json
    jq .error /tmp/daos_system_error.json
}

function daos_wait_start()
{
    local result=$(get_daos_system_error)
    return $result =~ "storage format required"
}

# parameter 1: number of seconds the timeout waits
# parameter 2: function that returns 0 when the condition has been satisfied
# parameter 3: message to be displayed upon timeout
function wait_for()
{
    local timeout_limit=$1
    local counter=0
    $2
    while [[ ! $? == 0 ]]; do
        if [ $counter -ge $timeout_limit ]; then
            echo "Timeout: $3"
            exit 1
        fi
        sleep 1
        $2
    done
}

function daos_start()
{
    initialize_daos_bin
    require_variables DAOS_BIN COMMAND_PREFIX

    $COMMAND_PREFIX mkdir -p /var/run/daos_server
    $COMMAND_PREFIX mkdir -p /var/run/daos_agent
    $COMMAND_PREFIX ${DAOS_BIN}/daos_server start &
    $COMMAND_PREFIX ${DAOS_BIN}/daos_agent start &
    # the response will contain "unable to contact the DAOS Management Service" while its initializing
    # once the response contains "storage format required", the system is ready for formatting
    wait_for 20 daos_wait_start "DAOS system failed to start"
    # local result=$(get_daos_system_error)    
    # while [[ ! $result =~ "storage format required" ]]; do
    #     result=$(get_daos_system_error)
    #     sleep 1
    # done
}

COMMAND_PREFIX=sudo
daos_start
