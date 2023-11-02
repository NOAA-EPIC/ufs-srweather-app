#
# bash functions to support CI/CD jobs for ufs-srweather-app (SRW) 
# Usage:
#     export NODE_NAME=<build_node>
#     export SRW_COMPILER="intel" | "gnu"
#     [SRW_DEBUG=true] source path/to/scripts/srw_functions.sh
#

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

if [[ ${SRW_DEBUG} == true ]] ; then
    echo "script_file=$(pwd)/${BASH_SOURCE[0]}"
    #echo "script_dir=$script_dir"
    echo "export NODE_NAME=${NODE_NAME}"
    echo "export WORKSPACE=${WORKSPACE}"
    echo "export SRW_APP_DIR=${SRW_APP_DIR}"
    echo "export SRW_PLATFORM=${SRW_PLATFORM}"
    echo "export SRW_COMPILER=${SRW_COMPILER}"
    grep "^function " ${BASH_SOURCE[0]}
fi

function SRW_git_clone() # clone a repo [ default: ufs-srweather-app -b develop ] ...
{
    local _REPO_URL=${1:-"https://github.com/ufs-community/ufs-srweather-app.git"}
    local _BRANCH=${2:-"develop"}
    git clone ${CLONE_OPT:-"--quiet"} ${_REPO_URL} $(basename ${_REPO_URL} .git) -b ${_BRANCH}
}

function SRW_git_commit() # Used to adjust the repo COMMIT to start building from ...
{
    local _COMMIT=$1
    [[ -n ${_COMMIT} ]] || return 0
    # if we have the "gh" command, use it to see if COMMIT is a PR# to pull ...
    # otherwise, use "git fetch" to see if COMMIT is a PR# to pull ...
    which gh 2>/dev/null && gh pr checkout ${_COMMIT} || \
    git fetch origin pull/${_COMMIT}/head:pr/${_COMMIT}
    # if we succeeded pulling a PR#, switch to it ...
    # otherwise, COMMIT must have been either a branch or tag or SHA1 hash ...
    git checkout pr/${_COMMIT} 2>/dev/null || git checkout ${_COMMIT}
}

function SRW_get_branch_name() {
    local _BRANCH=$1
    [[ -n $_BRANCH ]] || _BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [[ HEAD = $_BRANCH ]] && _REF="$(git symbolic-ref --short HEAD 2>/dev/null)" && _BRANCH=$_REF # && echo "REF=$_REF" || echo "No matching REF for $_BRANCH"
    [[ -n $_BRANCH ]] || _BRANCH=develop
    echo "$_BRANCH"
}

function SRW_list_repos() # show a table of latest commit IDs of all repos/sub-repos at PWD
{
    local comment="$1" # pass in a "brief message string ..."
    echo "$comment"
    for repo in $(find . -name .git -type d | sort) ; do
    (
        cd $(dirname $repo)
        SUB_REPO_NAME=$(git config --get remote.origin.url | sed "s|https://github.com/||g" | sed "s|.git$||g")
        SUB_REPO_STR=$(printf "%-40s%s\n" "$SUB_REPO_NAME~" "~" | tr " ~" "  ")
        SUB_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        git log -1 --pretty=tformat:"# $SUB_REPO_STR %h:$SUB_BRANCH_NAME %d %s [%ad] <%an> " --abbrev=8 --date=short
    )
    done
}

function SRW_has_cron_entry() # Are there any srw-build-* experiment crons running?
{
    local dir=$1
    crontab -l | grep "ufs-srweather-app/srw-build-${SRW_COMPILER:-"intel"}/expt_dirs/$dir"
}

function SRW_clean() {
    if [[ ${clean} == true ]] && [[ -d ${SRW_APP_DIR:-"."}/.git ]] ; then
    (
        cd ${SRW_APP_DIR:-"."}
        set -x
        pwd
        [[ -f ./devclean.sh ]] || return 1
        ./devclean.sh --clean --sub-modules
        git clean -f
        git clean -fd
    )
    fi
}

function SRW_activate_workflow() {
    #### Check - Activate the workflow environment ...
    echo "hostname=$(hostname)"
    echo "PWD=${PWD}"
    [[ ! -d .git/ ]] && echo "Not at source directory (.git)" && return 1
    echo "NODE_NAME=${NODE_NAME}"
    echo "SRW_PLATFORM=${SRW_PLATFORM}"
    echo "SRW_COMPILER=${SRW_COMPILER}"
    echo "LMOD_VERSION=${LMOD_VERSION}"
    set -x
    git log -1 --oneline
    if [[ ${SRW_PLATFORM} =~ gaea ]]; then
        [[ ${NODE_NAME} == Gaea ]] && source /lustre/f2/dev/role.epic/contrib/Lmod_init.sh
        [[ ${NODE_NAME} == GaeaC5 ]] && source /lustre/f2/dev/role.epic/contrib/Lmod_init_C5.sh
    else
        source etc/lmod-setup.sh ${SRW_PLATFORM}
    fi
    echo "LMOD_VERSION=${LMOD_VERSION}"
    module use ${PWD}/modulefiles
    [[ ${SRW_PLATFORM} =~ hera ]] && module load build_${SRW_PLATFORM}_${SRW_COMPILER}
    module load wflow_${SRW_PLATFORM}
    rc=$?
    conda activate workflow_tools
    module list
    set +x
    return $rc
}

function SRW_build() {
    #### Initialize
    echo hostname=$(hostname)
    echo WORKSPACE=${WORKSPACE}
    echo SRW_APP_DIR=${SRW_APP_DIR}
    echo SRW_PLATFORM=${SRW_PLATFORM}
    echo SRW_COMPILER=${SRW_COMPILER}
    echo SRW_PROJECT=${SRW_PROJECT}
    echo on_compute_node=${on_compute_node}
    rc=0
    (
    cd ${SRW_APP_DIR:-"."}
    pwd
    git log -1 --pretty=oneline
    #### SRW Build ####
    local WORKSPACE=${PWD}
    local status=0
    if [[ -x install_${SRW_COMPILER}/exec/ufs_model ]] ; then
        echo "Skipping Rebuild of SRW"
    else
        echo "Building SRW (${SRW_COMPILER}) on ${SRW_PLATFORM} (in ${WORKSPACE})"
        ./manage_externals/checkout_externals
        if [[ true != ${on_compute_node} ]] || [[ ${SRW_PLATFORM} =~ cheyenne ]] ; then
            set -x
	    cd tests
	    ./build.sh ${SRW_PLATFORM} ${SRW_COMPILER}
	    status=$?
	    cd -
            set +x
        else
            # Get ready to build SRW on a compute node ...
            node_opts="-A ${SRW_PROJECT} -t 1:20:00"
            [[ ${SRW_PLATFORM} =~ jet      ]] && node_opts="-A ${SRW_PROJECT} -t 3:20:00"
            [[ ${SRW_PLATFORM} =~ orion    ]] && node_opts="-p ${SRW_PLATFORM}"
            [[ ${SRW_PLATFORM} =~ hercules ]] && node_opts="-p ${SRW_PLATFORM}"
            set -x
	    cd tests
            srun -N 1 ${node_opts} -o build-%j.txt -e build-%j.txt ./build.sh ${SRW_PLATFORM} ${SRW_COMPILER}
            status=$?
	    cd -
            set +x
        fi
        echo "Build Successfully Completed on ${NODE_NAME}!"
    fi
    return $status;
    )
    rc=$?
    echo "SRW_build() status=$rc"
    return $rc
}

function SRW_run_workflow_tests() {
    rc=0
    cd ${SRW_APP_DIR:-"."}
    echo "PWD=${PWD}"
    echo "LMOD_VERSION=$LMOD_VERSION"
    
    set +e +u

    # clear out any prior tests ...
    rm -fr expt_dirs/grid*
    rm -f  tests/WE2E/WE2E_tests_*.yaml
    rm -f  tests/WE2E/WE2E_summary_*.txt
        
    if [[ -z ${SRW_WE2E_SINGLE_TEST} ]] ; then
            echo "Skipping Workflow E2E test"
    else
        # This sets the Graphic Plot generation ...
        if [[ ${SRW_WE2E_SINGLE_TEST} == "plot" ]] ; then
	    SRW_WE2E_SINGLE_TEST=grid_RRFS_CONUS_13km_ics_FV3GFS_lbcs_FV3GFS_suite_GFS_v16_plot
	    [[ "${SRW_PLATFORM}" =~ orion    ]] && SRW_WE2E_SINGLE_TEST=grid_RRFS_AK_13km_ics_FV3GFS_lbcs_FV3GFS_suite_GFS_v16_plot
	    [[ "${SRW_PLATFORM}" =~ hercules ]] && SRW_WE2E_SINGLE_TEST=grid_RRFS_AK_13km_ics_FV3GFS_lbcs_FV3GFS_suite_GFS_v16_plot
	    [[ "${SRW_PLATFORM}" =~ gaea     ]] && SRW_WE2E_SINGLE_TEST=grid_SUBCONUS_Ind_3km_ics_RAP_lbcs_RAP_suite_RRFS_v1beta_plot
            [[ "${SRW_PLATFORM}" =~ cheyenne ]] && [[ "${SRW_COMPILER}" == gnu ]] && SRW_WE2E_SINGLE_TEST=grid_RRFS_CONUS_25km_ics_FV3GFS_lbcs_FV3GFS_suite_GFS_v17_p8_plot
            cp tests/WE2E/test_configs/grids_extrn_mdls_suites_community/config.$SRW_WE2E_SINGLE_TEST.yaml \
	        tests/WE2E/test_configs/grids_extrn_mdls_suites_community/config.plot.yaml
         fi

        set -x
        if [[ ${SRW_WE2E_SINGLE_TEST} == "coverage" ]] || [[ ${SRW_WE2E_SINGLE_TEST} == "comprehensive" ]] ; then
	    test_type=${SRW_WE2E_SINGLE_TEST}
	else
            #### Changes to allow for a single E2E test ####
            test_type="single"
 	    if [[ ${SRW_WE2E_SINGLE_TEST} =~ skill-score ]] ; then
                SRW_WE2E_SINGLE_TEST=grid_SUBCONUS_Ind_3km_ics_FV3GFS_lbcs_FV3GFS_suite_WoFS_v0
	    fi
	    echo "${SRW_WE2E_SINGLE_TEST}" > tests/WE2E/single
	fi
        set +x

        echo "Running Workflow E2E Test ${SRW_WE2E_SINGLE_TEST} on ${NODE_NAME}!"

        # Start a test ...
	[[ -n ${ACCOUNT} ]] || ACCOUNT=${SRW_PROJECT}
        echo "E2E Testing SRW (${SRW_COMPILER}) on ${SRW_PLATFORM} using ACCOUNT=${ACCOUNT} (in ${workspace})"
        set -x
	umask 002   # enabling group-write permission on new files/dirs might help on AWS
	umask

  	# Test directories
	we2e_experiment_base_dir="${PWD}/expt_dirs"
	we2e_test_dir="${PWD}/tests/WE2E"
	nco_dir="${PWD}/nco_dirs"

	cd ${we2e_test_dir}
	# Progress file
	progress_file="${PWD}/we2e_test_results-${SRW_PLATFORM}-${SRW_COMPILER}.txt"
 
	# Run the end-to-end tests.
	./setup_WE2E_tests.sh ${SRW_PLATFORM} ${SRW_PROJECT} ${SRW_COMPILER} ${test_type} \
	    --expt_basedir=${we2e_experiment_base_dir} \
	    --opsroot=${nco_dir} | tee ${progress_file}
	rc=$?
 	cd -
        echo "Completed Workflow Tests on ${NODE_NAME}! rc=$rc"
    fi
    set +x
    return $rc
}

#[[ ${SRW_DEBUG} == true ]] && ( set | grep "()" | grep "^SRW_" )