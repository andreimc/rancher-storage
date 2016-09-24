#!/bin/bash

. /opt/rancher/common.sh

set -e

# environment variables
: ${GANESHA_EXPORT:="/"}
: ${GANESHA_PSEUDO_EXPORT:="/"}
: ${GANESHA_CONFIG:="/etc/ganesha/ganesha.conf"}
: ${GANESHA_LOGFILE:="/dev/stdout"}
: ${GANESHA_OPTIONS:="-N NIV_DEBUG"} # NIV_DEBUG, NIV_EVENT, NIV_WARN

init_rpc() {
    echo "* starting rpcbind"
    if [ ! -x /run/rpcbind ] ; then
        install -m755 -g 32 -o 32 -d /run/rpcbind
    fi
    rpcbind || return 0
    rpc.statd -L || return 0
    rpc.idmapd || return 0
    sleep 1
}

init_dbus() {
    echo "* starting dbus"
    if [ ! -x /var/run/dbus ] ; then
        install -m755 -g 81 -o 81 -d /var/run/dbus
    fi
    rm -f /var/run/dbus/*
    rm -f /var/run/messagebus.pid
    dbus-uuidgen --ensure
    dbus-daemon --system --fork
    sleep 1
}

# About pNFS
# Ganesha by default is configured as pNFS DS.
# A full pNFS cluster consists of multiple DS
# and one MDS (Meta Data server). To implement
# this we need to deploy multiple Ganesha NFS
# and then configure one of them as MDS:
# GLUSTER { PNFS_MDS = ${WITH_PNFS}; }

bootstrap_config() {
    echo "* writing configuration"
    cat <<END >${GANESHA_CONFIG}

NFSV4 { Graceless = true; }
EXPORT{
    Export_Id = 2;
    Path = "${EXPORT_PATH}";
    FSAL {
        name = VFS;
    }
    Access_type = RW;
    Disable_ACL = true;
    Squash = "${SQUASH_MODE}";
    Pseudo = "/${EXPORT_NAME}";
    #Anonymous_uid = ${ANON_UID};
    #Anonymous_gid = ${ANON_GID};
    #Protocols = "NFS4";
    #Transports = "TCP";
    SecType = "sys";
}

END
}

sleep 0.5

ALLMETA=$(curl -sS -H 'Accept: application/json' ${META_URL})
EXPORT_NAME=$(echo ${ALLMETA} | jq -r '.self.service.metadata.export_name')
SQUASH_MODE=$(echo ${ALLMETA} | jq -r '.self.service.metadata.squash_mode')
STORAGE_PATH="/data/nfs"
EXPORT_PATH="${STORAGE_PATH}/${EXPORT_NAME}"

if [ ! -f ${EXPORT_PATH} ]; then
    mkdir -p "${EXPORT_PATH}"
fi

echo "initializing Ganesha NFS server"
echo "=================================="
echo "export name: ${EXPORT_NAME}"
echo "export path: ${EXPORT_PATH}"
echo "=================================="

bootstrap_config
init_rpc
init_dbus

echo "generated Ganesha-NFS config:"
cat ${GANESHA_CONFIG}

echo "* starting Ganesha-NFS"
exec /usr/bin/ganesha.nfsd -F -L ${GANESHA_LOGFILE} -f ${GANESHA_CONFIG} ${GANESHA_OPTIONS}
