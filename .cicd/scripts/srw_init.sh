#!/usr/bin/env bash
#
# A unified init script for the SRW application. This script is expected to
# fetch initial source code for the SRW application for all supported platforms.
#
set -e -u -x

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

# Get repository root from Jenkins WORKSPACE variable if set, otherwise, set
# relative to script directory.
declare workspace
if [[ -n "${WORKSPACE}/${SRW_PLATFORM}" ]]; then
    workspace="${WORKSPACE}/${SRW_PLATFORM}"
else
    workspace="$(cd -- "${script_dir}/../.." && pwd)"
fi

# Normalize Parallel Works cluster platform value.
declare platform
if [[ "${SRW_PLATFORM}" =~ ^(az|g|p)clusternoaa ]]; then
    platform='noaacloud'
else
    platform="${SRW_PLATFORM}"
fi

# fetch initial source
cd ${workspace}
set +e
/usr/bin/time -p -o ${WORKSPACE}/${SRW_PLATFORM}-time-srw_init.txt ./manage_externals/checkout_externals
init_exit=$?
set -e
cd -

exit $init_exit