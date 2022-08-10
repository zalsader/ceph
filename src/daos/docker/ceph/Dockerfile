# Copyright 2022 Seagate Corporation
# All rights reserved.
#
# 'recipe' for Docker to build an image of radosgw + DAOS
#

# Pull base image
ARG BASE_DISTRO=daos-single-host:latest
FROM $BASE_DISTRO
LABEL maintainer="seagate-daos@seagate.com"

# get & build the ceph source
COPY ccache.conf /etc/ccache.conf
ENV SOURCE_DATE_EPOCH=946684800
RUN cd /opt && sudo mkdir -p ceph && sudo chmod 777 ceph && git clone --recurse https://github.com/zalsader/ceph --branch add-daos-rgw-sal
RUN cd /opt/ceph && ./install-deps.sh
RUN pip3 install cython prettytable
RUN cd /opt/ceph && cmake3 -GNinja -DPC_DAOS_INCLUDEDIR=${DAOS_PATH}/include -DPC_DAOS_LIBDIR=${DAOS_PATH}/lib64 -DWITH_PYTHON3=3.6 -DWITH_RADOSGW_DAOS=YES -DWITH_CCACHE=ON -DENABLE_GIT_VERSION=OFF -B build && cd build && ninja vstart
RUN cd /opt/ceph/build && sudo MDS=0 RGW=1 ../src/vstart.sh -f -n --without-dashboard
RUN cd /opt/ceph/build && sudo ../src/stop.sh
COPY ceph.sed /opt/ceph/build
RUN cd /opt/ceph/build && sed -i -f ceph.sed ceph.conf
ENV CEPH_PATH=/opt/ceph
