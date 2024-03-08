#!/bin/bash
export SINGULARITYENV_FI_PROVIDER=tcp
export SINGULARITY_SHELL=/usr/share/lmod/lmod/init/bash
export SINGULARITYENV_PREPEND_PATH="/lustre/ufs-srweather-app/bin"
img="/lustre/ubuntu20.04-intel-srwapp-release-public-v2.2.0.img"
cmd=$(basename "$0")
arg="$@"
echo running: singularity exec "${img}" $cmd $arg
/usr/bin/singularity exec -B /home -B /lustre "${img}" $cmd $arg
