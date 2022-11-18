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
    echo "export SRW_COMPILER=${SRW_COMPILER}"
    grep "^function " ${BASH_SOURCE[0]}
fi

function SRW_list_repos() # show a table of latest commit IDs of all repos/sub-repos at PWD
{
    local comment="$1"
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

function SRW_wflow_status() # [internal] used to determine state of an e2e test
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

function SRW_check_progress() # [internal] used to report total progress of all e2e tests
{
    local status_file="$1"
    local log_file=""
    local result=""
    local rc=0
    local workspace=${WORKSPACE:-"."}
    export WE2E_dir=${workspace}/regional_workflow/tests/WE2E
    
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
    local workspace=${WORKSPACE:-"."}
    export WE2E_dir=${workspace}/regional_workflow/tests/WE2E

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
        for dir in $(cat ${workspace}/regional_workflow/tests/WE2E/expts_file.txt 2>/dev/null) ; do
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
}

function SRW_get_details() # Use rocotostat to generate detailed test results
{
    local startTime="$1"
    local opt="$2"
    local log_file=""
    local workspace=${WORKSPACE:-"."}
    echo ""
    echo "#### started $startTime"
    echo "#### checked $(date)"
    echo "#### ${SRW_COMPILER}-${NODE_NAME,,} ${JOB_NAME:-$(git config --get remote.origin.url 2>/dev/null)} -b ${REPO_BRANCH:-${GIT_BRANCH:-$(git symbolic-ref --short HEAD 2>/dev/null)}}"
    echo "#### rocotostat -w "FV3LAM_wflow.xml" -d "FV3LAM_wflow.db" -v 10 $opt"
    echo ""
    for dir in $(cat ${workspace}/regional_workflow/tests/WE2E/expts_file.txt 2>/dev/null) ; do
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
            regional_workflow/tests/WE2E/expts_file.txt \
	    --exclude=fix_am --exclude=fix_lam --exclude=_old_ expt_dirs
        if [[ 0 == $? ]] ; then
            ( cd ${SRW_SAVE_DIR}/${NODE_NAME} && rm -f latest && ln -s $day_of_week latest )
        fi
    fi
}

function SRW_plot_allvars() # Plot data from SRW E2E test, and prepare latest ones for archiving.
{
    local dir="$1"
    local PDATA_PATH="$2"
    local workspace=${WORKSPACE:-"."}
    (
    cd ${workspace}/regional_workflow/ush/Python
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
