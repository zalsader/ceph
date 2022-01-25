# DAOS
Standalone Rados Gateway (RGW) on [DAOS](http://daos.io/) (Experimental)


## CMake Option
Add below cmake option

    -DWITH_RADOSGW_DAOS=ON 


## Build

    cd build
    ninja [vstart]


## Running Test cluster
Edit ceph.conf to add below option

    [client]
        rgw backend store = daos

Restart vstart cluster or just RGW server

    [..] RGW=1 ../src/vstart.sh -d

The above configuration brings up RGW server on DAOS and creates testid user to be used for s3 operations.
