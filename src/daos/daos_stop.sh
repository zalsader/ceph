#!/bin/bash

source $CEPH_PATH/src/daos/require_variables.sh

daos_stop()
{
    require_variables DAOS_BIN
    # wait until daos_engine is not running
    sudo ${DAOS_BIN}dmg system stop --force
    local check_command='ps -e | grep daos_engine'
    eval "$check_command"
    while [[ $? == 0 ]]; do
        eval "$check_command"
    done
}
