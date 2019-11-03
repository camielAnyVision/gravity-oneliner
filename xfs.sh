#!/bin/bash


function newpartition {
    #new partition
    filesystem=$1
    partition="${filesystem}1"
    if [ -b "/dev/${filesystem}" ] ; then
        echo "The disk /dev/${filesystem} exist"
    else
        echo "The disk /dev/${filesystem} is not exist. will exit"
        exit 1
    fi
    
    
    if [ -e "/dev/${partition}" ] ; then
        echo "The partition /dev/${partition} is already exist"
    else
        echo "format the disk ${filesystem} with parted"
        parted -a optimal -s "/dev/${filesystem}" mklabel gpt mkpart primary xfs 0% 100%
        sleep 3
        echo "create new partition /dev/${partition}"
        mkfs -t xfs -i size=512 "/dev/${partition}"
    fi
}

function newmount {
    #new mount
    mountpoint=$1
    filesystem=$2
    partition="${filesystem}1"
    directoryIsMount=$(mountpoint "${mountpoint}" || true)
    if [[ ${directoryIsMount} == *"is a mountpoint"* ]] ; then
        echo "The mount ${mountpoint} is already mounted"
    else
        echo "create new directory ${mountpoint} for the mount"
        mkdir -p "${mountpoint}"
        if [[ ! $(grep "storage" "/etc/fstab") ]]; then
            echo "add the new partition /dev/${partition} --> ${mountpoint} into fstab"
            echo "/dev/${partition} ${mountpoint} xfs defaults,inode64,noatime,nodiratime,nofail 0 0" >> "/etc/fstab"
        fi
        echo "mount all"
        systemctl daemon-reload
        mount -a
    fi
}

function showhelp {
   echo "$@ -f <filesysem> -m <mountpoint>"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
output_file=""
verbose=0

while getopts "h?m:f:" opt; do
    case "$opt" in
    h|\?)
        showhelp
        exit 0
        ;;
    m)  mountpoint=$OPTARG
        ;;
    f)  filesysem=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ -z $mountpoint ] || [ -z $filesysem ]; then 
    echo "missing either filesysem || mountpoint parameter"
    echo "Example usage: <path to script>/xfs.sh -f sdb -m /storage"
    exit 1
fi

echo "mountpoint=$mountpoint, filesysem='$filesysem', Leftovers: $@"

newpartition $filesysem
newmount $mountpoint $filesysem
