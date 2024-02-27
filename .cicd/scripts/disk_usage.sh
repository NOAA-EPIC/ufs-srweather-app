#!/usr/bin/env bash

# Output a CSV report of disk usage on subdirs of some path
# Usage: 
#    [JOB_NAME=<ci_job>] [BUILD_NUMBER=<n>] [COMPILER_CHOICE=<intel>] [SRW_PLATFORM=<machine>] disk_usage [ depth [ size ] ]

function disk_usage() {
    local directory=${1:-${PWD}}
    local depth=${2:-1}
    local size=${3:-k}
    [[ -n ${SRW_PLATFORM} ]] || SRW_PLATFORM=$(hostname -s 2>/dev/null) || SRW_PLATFORM=$(hostname 2>/dev/null)
    echo "Disk usage: ${JOB_NAME}/${SRW_PLATFORM}/$(basename $directory)"
    (
    cd $directory || exit 1
    echo "Platform,Build,Owner,Group,Inodes,${size:-k}bytes,Access Time,Filename"
    du -Px -d ${depth:-1} --inode --exclude='./workspace' | \
        while read line ; do
            arr=($line); inode=${arr[0]}; filename=${arr[1]};
            echo "${SRW_PLATFORM}-${COMPILER_CHOICE:-compiler},${JOB_NAME:-ci}/${BUILD_NUMBER:-0},$(stat -c '%U,%G' $filename),${inode:-0},$(du -Px -s -${size:-k} --time $filename)" | tr '\t' ',' ;
        done | sort -t, -k5 -n #-r
    )
    echo ""
}

disk_usage $1 $2 $3
