#!/bin/bash
if [[ $RUN_DATE == "" ]]; then
    export RUN_DATE="$(date +"%Y-%m-%d")"
fi
if [[ $CONTAINER_NAME == "" ]]; then
    export CONTAINER_NAME="dgws3-$RUN_DATE"
fi
set -x

function start_docker_container()
{
    if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
        if [ "$(docker ps -aq -f status=exited -f name=${CONTAINER_NAME})" ]; then
            # cleanup
            docker rm ${CONTAINER_NAME}
            if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        fi
        # run your container
        docker run -it -d --privileged --cap-add=ALL -h docker-$CONTAINER_NAME --name $CONTAINER_NAME -v /dev:/dev dgw-s3-tests
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    fi

    docker start $CONTAINER_NAME
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
}

function start_daos_cortx_s3tests()
{
    # check for anything running as this may be a re-run
    PROCESSES=$(docker exec $CONTAINER_NAME  ps -e)
    if [[ ! $PROCESSES =~ daos_server ]]; then
        docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/daos_server start &
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/daos_agent &
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        sleep 5
        docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/dmg -i storage format
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        sleep 20
        docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/dmg pool create --size=4GB tank
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        sleep 10
        docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/ceph/build && sudo RGW=1 ../src/vstart.sh'
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        sleep 5
        docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/s3-tests && sh setup.sh'
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
        docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/s3-tests && sh run_tests.sh cleandaos restart 50 stop MISSING'
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    else
        docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/s3-tests && sh run_tests.sh summary'
        if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    fi
}

function copy_artifact()
{
    if [[ -e $RUN_DATE/$1 ]]; then
        sudo chmod 666 $RUN_DATE/$1
    fi
    docker cp $CONTAINER_NAME:/opt/s3-tests/$1 $RUN_DATE/
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
}

function copy_s3tests_artifacts()
{
    mkdir -p $RUN_DATE
    copy_artifact "test_summary.csv"
    copy_artifact "test_output.csv"
    copy_artifact "test_diff.csv"
}

function cleanup_container()
{
    docker stop $CONTAINER_NAME
    docker container rm $CONTAINER_NAME --force
}

function update_confluence_s3tests_page()
{
    if [[ $CONFLUENCE_UPDATE_EMAIL == "" ]] || [[ $CONFLUENCE_UPDATE_KEY == "" ]]; then
        echo "Confluence credentials not set, skipping update of page"
        return
    fi
    if [[ ! -e update_confluence.py ]]; then
        echo "python file not found in: $PWD"
        return
    fi
    python3 update_confluence.py $RUN_DATE/test_summary.csv
}

function cleanup_hugepages()
{
    # check the number of free hugepages.  These may need to be cleared
    # grep HugePages_Free /proc/meminfo
    sudo rm -f /dev/hugepages/spdk*
}

function reboot_jenkins_node()
{
    # reboots the host in 30 seconds but doesn't wait (jenkins build will not fail)
    (sudo bash -c "(sleep 30 && sudo shutdown -r now) &") &
}

cleanup_hugepages
hugepages=`grep HugePages_Free /proc/meminfo | grep -oE "[0-9]+"`
if [ $hugepages -lt 512 ]; then
    echo "Not enough free hugepages: $hugepages < 512, skipping run and attempting to reboot node"
else
    start_docker_container
    start_daos_cortx_s3tests
    copy_s3tests_artifacts
    update_confluence_s3tests_page
    # cleanup_container
fi
reboot_jenkins_node
