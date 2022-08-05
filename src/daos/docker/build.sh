#!/bin/bash
# daosrocky=`docker images | grep -o "daos-rocky"`
# if [[ ! $daosrocky == 'daos-rocky' ]]; then
#     docker build https://github.com/daos-stack/daos.git#master -f utils/docker/Dockerfile.el.8 -t daos-rocky
#     if [[ ! $? == 0 ]]; then exit 1; fi
# fi
# pushd daos
# docker build . -t "daos-single-host"
# if [[ ! $? == 0 ]]; then exit 1; fi
# popd

pushd ceph
docker build . -t "dgw-single-host"
if [[ ! $? == 0 ]]; then exit 1; fi
popd

pushd s3-tests
docker build . -t "dgw-s3-tests"
if [[ ! $? == 0 ]]; then exit 1; fi
popd
# sh test.sh
