#!/bin/bash
export RUN_DATE="$(date +"%Y-%m-%d")"
export CONTAINER_NAME="dgws3-$RUN_DATE"
#set -x

if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=${CONTAINER_NAME})" ]; then
        # cleanup
        docker rm ${CONTAINER_NAME}
    fi
    # run your container
    docker run -it -d --privileged --cap-add=ALL --name $CONTAINER_NAME -v /dev:/dev dgw-s3-tests
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
fi

#if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
docker start $CONTAINER_NAME
if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi

# check for anything running as this may be a re-run
PROCESSES=$(docker exec -it $CONTAINER_NAME  ps -ea)
if [[ $PROCESSES =~ daos_server ]]; then
    docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/daos_server start &
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/daos_agent &
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    sleep 3
    docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/dmg -i storage format
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    sleep 6
    docker exec -u 0 $CONTAINER_NAME /opt/daos/bin/dmg pool create --size=4GB tank
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    sleep 4
    docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/ceph/build && sudo RGW=1 ../src/vstart.sh'
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/s3-tests && sh setup.sh'
    if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
    docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/s3-tests && sh run_tests.sh stop MISSING'
else
    docker exec -u 0 $CONTAINER_NAME bash -c 'cd /opt/s3-tests && sh run_tests.sh summary'
fi

mkdir -p $RUN_DATE
docker cp $CONTAINER_NAME:/opt/s3-tests/test_summary.csv $RUN_DATE/
if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
docker cp $CONTAINER_NAME:/opt/s3-tests/test_output.csv $RUN_DATE/
if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
docker cp $CONTAINER_NAME:/opt/s3-tests/test_diff.csv $RUN_DATE/
if [[ ! $? == 0 ]]; then echo "failed"; exit 1; fi
