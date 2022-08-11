#!/bin/bash

source $CEPH_PATH/src/daos/require_variables.sh

daos_stop()
{
    require_variables DAOS_BIN COMMAND_PREFIX
    # wait until daos_engine is not running
    $COMMAND_PREFIX ${DAOS_BIN}/dmg system stop --force
    local check_command='ps -e | grep daos_engine'
    eval "$COMMAND_PREFIX $check_command"
    while [[ $? == 0 ]]; do
        eval "$COMMAND_PREFIX $check_command"
    done
}
