#!/bin/bash

source $CEPH_PATH/src/daos/require_variables.sh

daos_erase()
{
    require_variables DAOS_BIN COMMAND_PREFIX
    local result=0
    $COMMAND_PREFIX ${DAOS_BIN}/dmg system erase
    while [ $result -ge 0 ]; do
        # loop until there is an error
        result=`$COMMAND_PREFIX ${DAOS_BIN}/dmg system query --json | jq .status`
        sleep 1
    done
}
