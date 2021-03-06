#!/bin/bash

# mountpoints for iso image and storage device
mounts=("/tmp/iso" "/tmp/usb")

# check to if the script is ran as root
if [[ $(id -u) -ne 0 ]]; then echo -e "\e[33mScript must be ran as root\033[0m"; exit 1; fi
# checks for iso image argument
if [[ -z $1 ]]; then
    # echos error and exits
    echo -e "\e[33mSpecify path to iso image: $0 /path/to/iso\033[0m"
    exit 1
# checks if iso image exists
elif [[ ! -f $1 ]]; then
    # echos error and exits
    echo -e "\e[33m$1 not found \033[0m"
    exit 1
# checks if file isn't an iso image
elif ! file --mime-type "$1" | grep -q x-iso9660-image; then
    # echos error and exits
    echo -e "\e[33m$1 is not an iso image \033[0m"
    exit 1
fi

# main while loop
while true; do
    # get list of storage devices from lsblk
    disks=($(lsblk -dnp --output NAME) "Quit")
    echo "Choose a device"
    # select statement for disks
    select option in ${disks[@]}; do
        # exit if Quit is selected
        if [[ $option == "Quit" ]]; then exit 1; fi
        # checks if option is valid
        if [[ -n $option ]]; then
            # assign selected disk to devices
            device=$option
            # break from select statement
            break
        else
            # echos error message
            echo "Invalid result"
        fi
    done
    # warning for selected storage device
    echo -ne "\e[0;31mAre you sure $device is the correct device? All data will be erased? [Y/n] \033[0m"
    read go
    if [[ ${go,,} = "y" ]]; then
        # stores list of partitions for the selected storage device
        partitions=($(lsblk $device -fnpr --output NAME | sed -n '1!p'))
        # loops through partitions
        for i in "${!partitions[@]}"; do
            # stores the mountpoint for partitions
            mountpoint=$(lsblk ${partitions[$i]} -dn --output MOUNTPOINT)
            # checks if a partition is mounted
            if [ -n "$(mount | grep ${partitions[$i]})" ]; then
                # asks user if they want to unmount the partition
                read -p "${partitions[$i]} is mounted on $mountpoint do you want to unmount it? [Y/n] " check
                if [[ ${check,,} = "y" ]]; then
                    # checks if partition is busy
                    fuser -s $mountpoint
                    if [ $? -eq 0 ]; then
                        echo -e "\e[33m$mountpoint: target is busy \033[0m"
                        # continue while loop
                        continue 2
                    else
                        # unmount partition
                        umount -v $mountpoint
                    fi
                else
                    # continues while loop if user doesn't want to unmount the partition
                    continue 2
                fi
            fi
        done
    # breaks from while loop
    break
    fi
done

# checks if parted is installed
which parted &> /dev/null
if [ $? -eq 0 ]; then
    # write mbr to storage device
    parted -s ${device} mklabel msdos
    # write partition to whole device
    parted -a opt ${device} mkpart primary ntfs 0% 100%
    # create NTFS partition on storage device
    mkfs.ntfs -L Windows -f ${partitions[0]}
else
    # echos error and exits
    echo -e "\e[33mError: Could not find GNU parted, Please install to continue. \033[0m"
    exit 1
fi

# loops through $mounts
for i in "${!mounts[@]}"; do
    # checks if directories for mounts don't exist
    if [ ! -d ${mounts[$i]} ]; then
        # creates directories for iso image and storage device
        mkdir -v ${mounts[$i]}
    fi
done

# mounts iso image
mount -vo loop $1 ${mounts[0]}
# mounts storage device
mount -v ${partitions[0]} ${mounts[1]}

# rsync data from iso image to storage device
rsync -Prv ${mounts[0]}/ ${mounts[1]}
echo "Syncing device, This could take a while."
# sync cached data to storage device
sync -f ${mounts[1]}

echo "Cleaning up..."
# loops through $mounts
for i in "${!mounts[@]}"; do
    # unmount iso image and storage device
    umount -v ${mounts[$i]}
    # removes mountpoint directories
    rmdir ${mounts[$i]}
done
