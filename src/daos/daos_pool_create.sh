#!/bin/bash

source $CEPH_PATH/src/daos/require_variables.sh

get_daos_pools_status()
{
    require_variables DAOS_BIN
    sudo ${DAOS_BIN}dmg system query --json > /tmp/daos_pools_status.json
    jq .status /tmp/daos_pools_status.json
}

get_daos_pools_state()
{
    require_variables DAOS_BIN
    sudo ${DAOS_BIN}dmg system query --json > /tmp/daos_pools_state.json
    jq .response.members[].state /tmp/daos_pools_state.json | sed 's/"//g'
}

daos_pool_create()
{
    require_variables DAOS_BIN
    sudo ${DAOS_BIN}dmg pool create --size=4GB tank
    local result=$(get_daos_pools_status)
    while [ ! $result -eq 0 ]; do
        result=$(get_daos_pools_status)
        sleep 10
    done

    result=$(get_daos_pools_state)
    while [[ ! $result == 'joined' ]] && [[ ! $result == 'Ready' ]]; do
        result=$(get_daos_pools_state)
        sleep 10
    done
}
