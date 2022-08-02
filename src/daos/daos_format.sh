#!/bin/bash

source $CEPH_PATH/src/daos/require_variables.sh

daos_format()
{
    require_variables DAOS_BIN
    local result=-1025
    sudo ${DAOS_BIN}dmg storage format --force
    while [ $result -lt 0 ]; do
        result=`sudo ${DAOS_BIN}dmg system query --json | jq .status`
        sleep 1
    done
}
