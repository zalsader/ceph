#!/bin/bash

git_folder=$(dirname "$0")
pushd ${git_folder}
branch=`git branch --show-current`
popd
default_branch='add-daos-rgw-sal'

function usage()
{
    # turn off echo
    set +x

    echo ""
    echo "./build-dev.sh"
    echo -e "\t-h --help"
    echo -e "\t-b --branch=<development_ceph_branch>"
    echo ""
}

while (( $# ))
    do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit 0
            ;;
        -b | --branch)
            branch=$VALUE
            ;;
        *)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
    esac
    shift
done

function get_s3_dockerfile()
{
    if [[ $branch == $default_branch ]]; then
        echo "Dockerfile"
    else
        sed "s/dgw-single-host/dgw-single-dev/g" < Dockerfile > /tmp/Dockerfile.dev.s3
        echo "/tmp/Dockerfile.dev.s3"
    fi
}

function get_ceph_dockerfile()
{
    if [[ $branch == $default_branch ]]; then
        echo "Dockerfile"
    else
        sed "s/add-daos-rgw-sal/${branch}/g; s/daos-single-host/daos-single-dev/g" < Dockerfile > /tmp/Dockerfile.dev.ceph
        echo "/tmp/Dockerfile.dev.ceph"
    fi
}

if [[ $branch == '' ]]; then
    echo "Failed to identify/use the branch specified"
    exit 1
fi

daosrocky=`docker images | grep -o "daos-rocky"`
if [[ ! $daosrocky == 'daos-rocky' ]]; then
    docker build https://github.com/daos-stack/daos.git#master -f utils/docker/Dockerfile.el.8 -t daos-rocky
    if [[ ! $? == 0 ]]; then exit 1; fi
fi
pushd daos
docker build . -t "daos-single-dev"
if [[ ! $? == 0 ]]; then exit 1; fi
popd

pushd ceph
docker build . -t "dgw-single-dev" -f $(get_ceph_dockerfile)
if [[ ! $? == 0 ]]; then exit 1; fi
popd

pushd s3-tests
docker build . -t "dgw-s3-dev" -f $(get_s3_dockerfile)
if [[ ! $? == 0 ]]; then exit 1; fi
popd
