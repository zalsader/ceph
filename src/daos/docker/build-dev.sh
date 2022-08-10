#!/bin/bash
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
sed "s/add-daos-rgw-sal/docker-build/g s/daos-single-host/daos-single-dev/g" < Dockerfile > Dockerfile.dev
docker build . -t "dgw-single-dev" -f Dockerfile.dev
if [[ ! $? == 0 ]]; then exit 1; fi
popd

pushd s3-tests
sed "s/dgw-single-host/dgw-single-dev/g" < Dockerfile > Dockerfile.dev
docker build . -t "dgw-s3-dev" -f Dockerfile.dev
if [[ ! $? == 0 ]]; then exit 1; fi
popd
