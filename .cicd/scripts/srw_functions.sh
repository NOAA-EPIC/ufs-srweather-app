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
    # if we have the 'gh' command, use it to see if COMMIT is a PR# to pull ...
    # otherwise, use 'git fetch' to see if COMMIT is a PR# to pull ...
    which gh 2>/dev/null && gh pr checkout ${_COMMIT} || \
    git fetch origin pull/${_COMMIT}/head:pr/${_COMMIT}
    # if we succeeded pulling a PR#, switch to it ...
    # otherwise, COMMIT must have been either a branch or tag or SHA1 hash ...
    git checkout pr/${_COMMIT} 2>/dev/null || git checkout ${_COMMIT}
}

function SRW_list_repos() # show a table of latest commit IDs of all repos/sub-repos at PWD
{
    local comment="$1" # pass in a "brief message string ..."
    echo "$comment"
    for repo in $(find . -name .git -type d | sort) ; do
    (
        cd $(dirname $repo)
        SUB_REPO_NAME=$(git config --get remote.origin.url | sed 's|https://github.com/||g' | sed 's|.git$||g')
        SUB_REPO_STR=$(printf "%-40s%s\n" "$SUB_REPO_NAME~" "~" | tr ' ~' '  ')
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
    if [[ ${clean} == true ]] && [[ -d ${SRW_APP_DIR}/.git ]] ; then
    (
        cd ${SRW_APP_DIR}
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
        echo SRW_PROJECT=${SRW_PROJECT}
        rc=0
        (
            cd ${SRW_APP_DIR}
                      #### SRW Build ####
                      export WORKSPACE=${PWD}
                      local status=0
                      if [[ -x install_${SRW_COMPILER}/exec/ufs_model ]] ; then
                          echo "Skipping Rebuild of SRW"
                      else
                          #### Change to enable hercules as a supported platform ...
                          grep ' hercules ' ./tests/build.sh || sed 's/ orion / orion hercules /1' -i ./tests/build.sh
                          
                          echo "Building SRW (${SRW_COMPILER}) on ${SRW_PLATFORM} (in ${WORKSPACE})"
                          ./manage_externals/checkout_externals
						  if [[ ${on_compute_node} == true ]] && [[ ${SRW_PLATFORM} != cheyenne ]] ; then
                              # Get ready to build SRW on a compute node ...
                              node_opts="-A ${SRW_PROJECT} -t 1:20:00"
                              [[ ${SRW_PLATFORM} =~ jet    ]] && node_opts="-A ${SRW_PROJECT} -t 3:20:00"
                              [[ ${SRW_PLATFORM} =~ orion    ]] && node_opts="-p ${SRW_PLATFORM}"
                              [[ ${SRW_PLATFORM} =~ hercules ]] && node_opts="-p ${SRW_PLATFORM}"
                              set -x
                              srun -N 1 ${node_opts} -o build-%j.txt -e build-%j.txt .cicd/scripts/srw_build.sh
                              status=$?
                              set +x
                          else
                              set -x
                              .cicd/scripts/srw_build.sh
                              status=$?
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
    cd ${SRW_APP_DIR}
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
        #### Changes to allow for a single E2E test ####
        #sed -z 's/#\nset /#\n[[ -n "${SRW_WE2E_SINGLE_TEST}" ]] || export SRW_WE2E_SINGLE_TEST=""\nset /1' -i .cicd/scripts/srw_test.sh
        #sed -z 's/"coverage"\nfi\n\n/"coverage"\nfi\n[[ -n "${SRW_WE2E_SINGLE_TEST}" ]] && test_type="${SRW_WE2E_SINGLE_TEST}"\n\n/1' -i .cicd/scripts/srw_test.sh
        #sed -z 's/"fundamental"\nfi\n\n/"fundamental"\nfi\n[[ -n "${SRW_WE2E_SINGLE_TEST}" ]] && test_type="${SRW_WE2E_SINGLE_TEST}"\n\n/1' -i .cicd/scripts/srw_test.sh
        sed -z 's/test_type="coverage"/test_type="single"/1' -i .cicd/scripts/srw_test.sh
        echo "${SRW_WE2E_SINGLE_TEST}" > tests/WE2E/single
        set +x

        echo "Running Workflow E2E Test ${SRW_WE2E_SINGLE_TEST} on ${NODE_NAME}!"

        # Start a test ...
        [[ ${SRW_PLATFORM} =~ hercules ]] && ACCOUNT="epic" || ACCOUNT=${SRW_PROJECT}
        echo "E2E Testing SRW (${SRW_COMPILER}) on ${SRW_PLATFORM} using ACCOUNT=${ACCOUNT} (in ${workspace})"
        set -x
        SRW_WE2E_COMPREHENSIVE_TESTS=false WORKSPACE=${PWD} SRW_PROJECT=${ACCOUNT} .cicd/scripts/srw_test.sh
        set +x
        echo "Completed Workflow Tests on ${NODE_NAME}!"
    fi
}

#### Below are legacy functions for public-v2.1.0
function SRW_load_miniconda() # EPIC platforms should have miniconda3 available to load
{
    local EPIC_PLATFORM=${1,,}
    if [[ -z $EPIC_PLATFORM ]] ; then
        echo "# Need a platform: e,g, Orion | Hera | clusternoaa | ..."
        return 1
        
    elif [[ $EPIC_PLATFORM == cheyenne ]] ; then
        module use /glade/work/epicufsrt/contrib/miniconda3/modulefiles

    elif [[ $EPIC_PLATFORM == orion ]] ;  then
        module use -a /work/noaa/epic-ps/role-epic-ps/miniconda3/modulefiles # append

    elif [[ $EPIC_PLATFORM == hera ]] ; then
        module use /scratch1/NCEPDEV/nems/role.epic/miniconda3/modulefiles

    elif [[ $EPIC_PLATFORM == jet ]] ; then
        module use /mnt/lfs4/HFIP/hfv3gfs/role.epic/miniconda3/modulefiles

    elif [[ $EPIC_PLATFORM == gaea ]] ;  then
        module use /lustre/f2/dev/role.epic/contrib/modulefiles

    elif [[ $EPIC_PLATFORM =~ clusternoaa ]] || [[ $EPIC_PLATFORM =~ noaacloud ]] ;  then
        module use /contrib/EPIC/miniconda3/modulefiles

    else
        echo "#### Platform '${EPIC_PLATFORM}' not yet supported."
        return 1
    fi
    module load miniconda3/4.12.0
}

function SRW_activate_env() # conda activate regional_workflow [ on an EPIC platform ] ...
{
    local EPIC_PLATFORM=${1,,}
    echo "#### SRW_activate_env(${EPIC_PLATFORM})"
    [[ -n ${EPIC_PLATFORM} ]] && SRW_load_miniconda ${EPIC_PLATFORM}
    conda activate regional_workflow
    which python && python --version
    conda info --envs
}

function SRW_wflow_status() # used to determine state of an e2e test
{
    local log_data="$1"
    local result=""
    local rc=0
    
    result=$(echo "$log_data" | cut -d: -f1 | tail -1)
    if [[ 0 == $? ]]; then
        rc=1
        echo "$result" | egrep -i 'IN PROGRESS|SUCCESS|FAILURE' > /dev/null || result=PENDING
        [[ $result =~ PROGRESS ]] && rc=1
        [[ $result =~ SUCCESS ]] && rc=0
        [[ $result =~ FAILURE ]] && rc=0
    else
        result="Not Found" && rc=9
    fi
    echo "$result"
    return $rc
}

function SRW_check_progress() # used to report total progress of all e2e tests
{
    local status_file="$1"
    local log_file=""
    local result=""
    local rc=0
    local workspace=${SRW_APP_DIR:-${WORKSPACE:-"$(pwd)"}/ufs-srweather-app}
    export WE2E_dir=${workspace}/tests/WE2E
    
    in_progress=false
    failures=0
    missing=0

    echo "# status_file=${status_file} [$([[ -f ${status_file} ]] && echo 'true' || echo 'false')]"
    echo "#### checked $(date)" | tee ${WE2E_dir}/expts_status.txt
    
    lines=$(egrep '^Checking workflow status of |^Workflow status: ' $status_file 2>/dev/null \
    | sed -z 's| ...\nWorkflow|:Workflow|g' \
    | sed 's|Checking workflow status of experiment ||g' \
    | sed 's|Workflow status:  ||g' \
    | tr -d '"' \
    | awk -F: '{print $2 ":" $1}' \
    | tee -a ${WE2E_dir}/expts_status.txt \
    )
    
    for dir in $(cat ${WE2E_dir}/expts_file.txt) ; do
        log_file=$(cd ${workspace}/expt_dirs/$dir/ 2>/dev/null && ls -1 log.launch_* 2>/dev/null)
	    [[ -n "$log_file" ]] && log_size=$(wc -c ${workspace}/expt_dirs/$dir/$log_file 2>/dev/null | awk '{print $1}') || log_size="'$log_file'"
        log_data="$(echo "$lines" | grep $dir)"
        result=$(SRW_wflow_status "$log_data")
        rc=$?
        echo "[$rc] $result $dir/$log_file [$log_size]"
        [[ 1 == $rc ]] && in_progress=true
        if [[ 0 == $rc ]]; then
            [[ $result =~ SUCCESS ]] || (( failures++ ))    # count FAILED test suites
        fi
        [[ 9 == $rc ]] && (( missing++ ))    # if log file is 'Not Found', count as missing
        #[[ 9 == $rc ]] && (( failures++ ))   # ... also count log file 'Not Found' as FAILED?
    done
    
    [[ $in_progress == true ]] && return $failures                # Not all completed ...
  
    # All Completed! return FAILURE count.
    return $failures
}

function SRW_e2e_status() # Get the status of E2E tests, and keep polling if they are't done yet ...
{
    local poll_frequency="${1:-120}"          # (seconds) ... polling frequency between results log scanning
    local num_log_lines="${2:-120}"
    local report_file="$3"
    local workspace=${SRW_APP_DIR:-${WORKSPACE:-"$(pwd)"}/ufs-srweather-app}
    export WE2E_dir=${workspace}/tests/WE2E

    echo "#### Do we have any tests ?"
    num_expts=$(cat ${WE2E_dir}/expts_file.txt 2>/dev/null | wc -l)
    [[ 0 == $num_expts ]] && echo "# No E2E expts files found." && return 13
    # If there are any test files, go poll their progress ... otherwise we are done.
    num_files=$(cd ${workspace}/expt_dirs 2>/dev/null && ls -1 */log.launch_* 2>/dev/null | wc -l)
    [[ 0 == $num_files ]] && echo "# No E2E test logs found." && return 14

    echo "#### Let's poll if any E2E test suites FAILED, and report a total JOB_STATUS"
    local rc=0
    local result="### []"
    local failures=0
    local completed=0
    local remaining=0
    local missing=0

    in_progress=true
    mkdir -p ${workspace}/tmp
    while [ $in_progress == true ] ; do
        ${WE2E_dir}/get_expts_status.sh expts_basedir=${workspace}/expt_dirs num_log_lines=$num_log_lines > ${workspace}/tmp/test-status.txt
        status_file=$(grep "  expts_status_fp = " ${workspace}/tmp/test-status.txt | cut -d\" -f2)
        mv ${status_file} ${workspace}/tmp/test-details.txt 2>/dev/null
        result=$(SRW_check_progress ${workspace}/tmp/test-details.txt)
        failures=$?
        completed=$(echo "$result" | egrep -v '^#|IN PROGRESS|PENDING' | wc -l)
        remaining=$(echo "$result" | egrep    'IN PROGRESS|PENDING' | wc -l)
        missing=$(  echo "$result" | egrep    'Not Found'   | wc -l)
        echo -e "$result\n expts=$num_expts completed=$completed failures=$failures remaining=$remaining missing=$missing"
        # if its just one test, show full status each poll ...
        [[ 1 == $num_expts ]] && \
        (
        for dir in $(cat ${workspace}/tests/WE2E/expts_file.txt 2>/dev/null) ; do
            ( cd ${workspace}/expt_dirs/$dir; rocotostat -w "FV3LAM_wflow.xml" -d "FV3LAM_wflow.db" -v 10 ; )
        done
        )
        if [[ $result =~ 'IN PROGRESS' ]] || [[ $result =~ 'PENDING' ]] ; then
            in_progress=true
            echo "#### ... poll every $poll_frequency seconds to see if all test suites are complete ..."
            sleep $poll_frequency
        else
            in_progress=false
        fi
    done
    echo -e "#### $(date)\n#### ${SRW_COMPILER}-${NODE_NAME} ${JOB_NAME} -b ${REPO_BRANCH:-${GIT_BRANCH:-$(git symbolic-ref --short HEAD)}}\n$result\n# expts=$num_expts completed=$completed failures=$failures missing=$missing" \
        | tee ${report_file}
    return ${failures}
}

function SRW_e2e_launch() # this will need to run within the ${WORKSPACE}/ufs-srweather-app/. directory (clone)
{
    local machine="$1"
    local compiler="$2"
    local account="$3"
    local srw_tests="$4"
    local expt_basedir="${5:-${SRW_APP_DIR}/expt_dirs}"
    local exec_subdir="${6:-exec}"
    local status=0
    
    [[ -n ${SRW_APP_DIR} ]] || local SRW_APP_DIR=${WORKSPACE:-"$(pwd)"}/ufs-srweather-app
    
    echo "SRW_e2e_launch(): SRW_APP_DIR=${SRW_APP_DIR}"
    
    cd ${SRW_APP_DIR}     || status=85
    cd tests/WE2E         || status=86
    cat -n expts_file.txt || status=87
    pwd
    
    # Start the SRW E2E tests
    if [[ 0 == $status ]] ; then
       set -x
       ./run_WE2E_tests.sh ${srw_tests} \
            machine="${machine}" \
            account="${account}" \
            compiler="${compiler}" \
            exec_subdir="${exec_subdir}" \
            expt_basedir="${expt_basedir}" \
            use_cron_to_relaunch="TRUE" \
            cron_relaunch_intvl_mnts="2" \
            verbose="FALSE" \
            debug="FALSE"
        status=$?
        set +x
    fi
    cd ${SRW_APP_DIR}
    
    return $status
}

function SRW_get_expts_status() # Verify E2E experiment dirs are collecting data
{
    local status=0

    local SRW_APP_DIR="$1"
    [[ -n ${SRW_APP_DIR} ]] || SRW_APP_DIR=${WORKSPACE:-"$(pwd)"}/ufs-srweather-app

    echo "SRW_get_expts_status(): SRW_APP_DIR=${SRW_APP_DIR}"

    if [[ 0 = $status ]]; then
        echo "# Delay a bit to let the expt logs start accumulating ..." && sleep 180  # should wait at least cron-interval + 30secs
        
        # Check if tests are progressing
        for dir in $(cat ${SRW_APP_DIR}/tests/WE2E/expts_file.txt 2>/dev/null) ; do
            ( cd ${SRW_APP_DIR}/expt_dirs/$dir; rocotostat -w "FV3LAM_wflow.xml" -d "FV3LAM_wflow.db" -v 10 ; )
        done

        # Generate initial status file
        cd ${SRW_APP_DIR}/tests/WE2E
        ./get_expts_status.sh expts_basedir="${SRW_APP_DIR}/expt_dirs" verbose="TRUE" #num_log_lines="100"
        status=$?      
        cd ${SRW_APP_DIR}
    fi
    
    return $status
}

function SRW_get_details() # Use rocotostat to generate detailed test results
{
    local startTime="$1"
    local opt="$2"
    local log_file=""
    local workspace=${SRW_APP_DIR:-${WORKSPACE:-"$(pwd)"}/ufs-srweather-app}
    echo ""
    echo "#### started $startTime"
    echo "#### checked $(date)"
    echo "#### ${SRW_COMPILER}-${NODE_NAME,,} ${JOB_NAME:-$(git config --get remote.origin.url 2>/dev/null)} -b ${REPO_BRANCH:-${GIT_BRANCH:-$(git symbolic-ref --short HEAD 2>/dev/null)}}"
    echo "#### rocotostat -w "FV3LAM_wflow.xml" -d "FV3LAM_wflow.db" -v 10 $opt"
    echo ""
    for dir in $(cat ${workspace}/tests/WE2E/expts_file.txt 2>/dev/null) ; do
        log_file=$(cd ${workspace}/expt_dirs/$dir/ 2>/dev/null && ls -1 log.launch_* 2>/dev/null)
        (
        echo "# rocotostat $dir/$log_file:"
        cd ${workspace}/expt_dirs/$dir/ && rocotostat -w "FV3LAM_wflow.xml" -d "FV3LAM_wflow.db" -v 10 $opt 2>/dev/null
        echo ""
        )
    done
    echo "####"
}

function SRW_save_tests() # Save SRW E2E tests to persistent storage, cluster_noaa hosts only 
{
    local SRW_SAVE_DIR="$1"
    echo "#### Saving SRW tests to ${SRW_SAVE_DIR}/${NODE_NAME}/day_of_week/expt_dirs.tar"
    [[ -n ${SRW_SAVE_DIR} ]] && [[ -d ${SRW_SAVE_DIR} ]] || return 1
    [[ -n ${NODE_NAME} ]] || return 2
    if [[ ${NODE_NAME} =~ cluster ]] && [[ -d ${SRW_SAVE_DIR} ]] ; then
        day_of_week="$(date '+%u')"
        mkdir -p ${SRW_SAVE_DIR}/${NODE_NAME}/$day_of_week || return 3
        echo "#### Saving SRW tests to ${SRW_SAVE_DIR}/${NODE_NAME}/$day_of_week/expt_dirs.tar"
        touch build_properties.txt workspace_properties.txt
        tar cvpf ${SRW_SAVE_DIR}/${NODE_NAME}/$day_of_week/expt_dirs.tar \
            build_properties.txt workspace_properties.txt \
            builder.txt \
            build-info.txt \
            launch-info.txt \
            test-results-*-*.txt test-details-*-*.txt \
            tests/WE2E/expts_file.txt \
	    --exclude=fix_am --exclude=fix_lam --exclude="*_old_*" expt_dirs
        if [[ 0 == $? ]] ; then
            ( cd ${SRW_SAVE_DIR}/${NODE_NAME} && rm -f latest && ln -s $day_of_week latest )
        fi
    fi
}

function SRW_plot_allvars() # Plot data from SRW E2E test, and prepare latest ones for archiving.
{
    local dir="$1"
    local PDATA_PATH="$2"
    local workspace=${SRW_APP_DIR:-${WORKSPACE:-"$(pwd)"}/ufs-srweather-app}
    (
    echo "#### WARNING! this is deprecated from 'develop'"
    cd ${workspace}/ush/Python || return 0
    source ${workspace}/expt_dirs/$dir/var_defns.sh >/dev/null
    echo "DATE_FIRST_CYCL=${DATE_FIRST_CYCL} CYCL_HRS=${CYCL_HRS} ALL_CDATES=${ALL_CDATES}"
    [[ -n ${ALL_CDATES} ]] || ALL_CDATES=$(echo ${DATE_FIRST_CYCL} | cut -c1-10)
    CDATE=${ALL_CDATES}
    echo "#### plot_allvars()  ${CDATE} ${EXTRN_MDL_LBCS_OFFSET_HRS} ${FCST_LEN_HRS} ${LBC_SPEC_INTVL_HRS} ${workspace}/expt_dirs/$dir ${PDATA_PATH}/NaturalEarth ${PREDEF_GRID_NAME}"
        python plot_allvars.py ${CDATE} ${EXTRN_MDL_LBCS_OFFSET_HRS} ${FCST_LEN_HRS} ${LBC_SPEC_INTVL_HRS} ${workspace}/expt_dirs/$dir ${PDATA_PATH}/NaturalEarth ${PREDEF_GRID_NAME}
        last=$(ls -rt1 ${workspace}/expt_dirs/$dir/${CDATE}/postprd/*.png | tail -1 | awk -F_ '{print $NF}')
        [[ -n ${last} ]] || return 1
        echo "# Saving plots from postprd/*${last} -> expt_plots/$dir/${CDATE}"
        ( cd ${workspace}/ && ls -rt1 -l expt_dirs/$dir/${CDATE}/postprd/*${last} ; )
        mkdir -p ${workspace}/expt_plots/$dir/${CDATE}
        cp -p ${workspace}/expt_dirs/$dir/${CDATE}/postprd/*${last} ${workspace}/expt_plots/$dir/${CDATE}/.
    )
}

#[[ ${SRW_DEBUG} == true ]] && ( set | grep "()" | grep "^SRW_" )
