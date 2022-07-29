#!/bin/bash
set -x

function usage()
{
    local BOOLEAN_VALUES="T[RUE]|Y[ES]|F[ALSE]|N[O]|1|0"
    echo ""
    echo "./test.sh"
    echo "\t-h --help"
    echo "\t-s --summary=$BOOLEAN_VALUES default=FALSE"
    echo "\t-u --update-confluence=$BOOLEAN_VALUES default=TRUE"
    echo "\t-c --cleanup-container=$BOOLEAN_VALUES default=TRUE"
    echo "\t-b --build-docker-images=$BOOLEAN_VALUES default=TRUE"
    echo ""
}

function set_boolean()
{
    declare -n foo=$1
    case ${2^^} in
        TRUE | T | YES | Y | 1)
            foo=true
            ;;
        FALSE | F | NO | N | 0)
            foo=false
            ;;
        *)
            if [[ "$2" == "" ]]; then
                # just flip the meaning
                foo=$(($foo ^ true))
            else
                echo "ERROR: unknown value \"$VALUE\""
                usage
                exit 1
            fi
            ;;
    esac
}

BUILDDOCKERIMAGES=true
SUMMARY=false
CLEANUP_CONTAINER=true
UPDATE_CONFLUENCE=true

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit 0
            ;;
        -b | --build-docker-images)
            set_boolean BUILDDOCKERIMAGES $VALUE
            ;;
        -s | --summary)
            set_boolean SUMMARY $VALUE
            ;;
        -c | --cleanup-container)
            set_boolean CLEANUP_CONTAINER $VALUE
            ;;
        -u | --update-confluence)
            set_boolean UPDATE_CONFLUENCE $VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ $RUN_DATE == "" ]]; then
    export RUN_DATE="$(date +"%Y-%m-%d")"
fi
if [[ $CONTAINER_NAME == "" ]]; then
    export CONTAINER_NAME="dgws3-$RUN_DATE"
fi

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
    if [[ ! $PROCESSES =~ daos_server ]] && [[ $SUMMARY == false ]]; then
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
    # reboot moved to the cleanup stage in jenkins - will always reboot even if the build fails)
    # reboots the host in 30 seconds but doesn't wait (jenkins build will not fail)
    (sudo bash -c "(sleep 30 && sudo shutdown -r now) &") &
}

GIT_ENUM_STATES=(UP_TO_DATE PULL_NEEDED PUSH_NEEDED DIVERGED)
tam=${#GIT_ENUM_STATES[@]}
for ((i=0; i < $tam; i++)); do
    name=${GIT_ENUM_STATES[i]}
    declare -r ${name}=$i
done

function get_git_status()
{
    pushd $1
    git remote update

    local LOCAL=$(git rev-parse @)
    local REMOTE=$(git rev-parse "@{u}")
    local BASE=$(git merge-base @ "@{u}")
    local RESULT

    if [ $LOCAL = $REMOTE ]; then
        RESULT=$UP_TO_DATE    # echo "Up-to-date"
    elif [ $LOCAL = $BASE ]; then
        RESULT=$PULL_NEEDED    # echo "Need to pull"
        git pull
    elif [ $REMOTE = $BASE ]; then
        RESULT=$PUSH_NEEDED    # echo "Need to push"
    else
        RESULT=$DIVERGED    # echo "Diverged"
    fi
    popd
    return $RESULT
}

function build_docker_images()
{
    DAOS_BUILT=0
    CEPH_BUILT=0
    get_git_status /opt/daos
    DAOS_GIT=$?
    docker inspect -f '{{ .Created }}' daos-rocky
    DAOS_ROCKY=$?
    docker inspect -f '{{ .Created }}' daos-single-host
    DAOS_SINGLE_HOST=$?
    if [[ $DAOS_GIT == $PULL_NEEDED ]] || [[ $DAOS_ROCKY != 0 ]] || [[ $DAOS_SINGLE_HOST != 0 ]]; then
        pushd daos
        docker build https://github.com/daos-stack/daos.git#master -f utils/docker/Dockerfile.el.8 -t daos-rocky
        if [[ ! $? == 0 ]]; then exit 1; fi
        docker build . -t "daos-single-host"
        if [[ ! $? == 0 ]]; then exit 1; fi
        DAOS_BUILT=1
        popd
    fi
    get_git_status /opt/ceph
    CEPH_GIT=$?
    docker inspect -f '{{ .Created }}' dgw-single-host
    DGW_SINGLE=$?
    if [[ $DAOS_BUILT != 0 ]] || [[ $CEPH_GIT == $PULL_NEEDED ]] || [[ $DGW_SINGLE != 0 ]]; then
        pushd ceph
        docker build . -t "dgw-single-host"
        if [[ ! $? == 0 ]]; then exit 1; fi
        CEPH_BUILT=1
        popd
    fi
    get_git_status /opt/s3-tests
    S3TESTS_GIT=$?
    docker inspect -f '{{ .Created }}' dgw-s3-tests
    DGW_S3TESTS=$?
    if [[ $CEPH_BUILT != 0 ]] || [[ $S3TESTS_GIT == $PULL_NEEDED ]] || [[ $DGW_S3TESTS != 0 ]]; then
        pushd s3-tests
        docker build . -t "dgw-s3-tests"
        if [[ ! $? == 0 ]]; then exit 1; fi
        popd
    fi

    # remove all of the extra images lying around
    docker rmi $(docker images -f "dangling=true" -q)
}

cleanup_hugepages
hugepages=`grep HugePages_Free /proc/meminfo | grep -oE "[0-9]+"`
if [ $hugepages -lt 512 ]; then
    echo "Not enough free hugepages: $hugepages < 512, skipping run, reboot node required"
else
    if [[ $BUILDDOCKERIMAGES == true ]]; then
        build_docker_images
    fi
    start_docker_container
    start_daos_cortx_s3tests
    copy_s3tests_artifacts
    if [[ $UPDATE_CONFLUENCE == true ]]; then
        update_confluence_s3tests_page
    fi
    if [[ $CLEANUP_CONTAINER == true ]]; then
        cleanup_container
    fi
fi
