#!/bin/bash
# 
if [[ ! "$CEPH_PATH" =~ . ]];
then
    CEPH_PATH=/opt/ceph
fi

# colorful output: https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Bold
BBlack='\033[1;30m'       # Black
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
BBlue='\033[1;34m'        # Blue
BPurple='\033[1;35m'      # Purple
BCyan='\033[1;36m'        # Cyan
BWhite='\033[1;37m'       # White

# Underline
UBlack='\033[4;30m'       # Black
URed='\033[4;31m'         # Red
UGreen='\033[4;32m'       # Green
UYellow='\033[4;33m'      # Yellow
UBlue='\033[4;34m'        # Blue
UPurple='\033[4;35m'      # Purple
UCyan='\033[4;36m'        # Cyan
UWhite='\033[4;37m'       # White

# Background
On_Black='\033[40m'       # Black
On_Red='\033[41m'         # Red
On_Green='\033[42m'       # Green
On_Yellow='\033[43m'      # Yellow
On_Blue='\033[44m'        # Blue
On_Purple='\033[45m'      # Purple
On_Cyan='\033[46m'        # Cyan
On_White='\033[47m'       # White

# High Intensity
IBlack='\033[0;90m'       # Black
IRed='\033[0;91m'         # Red
IGreen='\033[0;92m'       # Green
IYellow='\033[0;93m'      # Yellow
IBlue='\033[0;94m'        # Blue
IPurple='\033[0;95m'      # Purple
ICyan='\033[0;96m'        # Cyan
IWhite='\033[0;97m'       # White

# Bold High Intensity
BIBlack='\033[1;90m'      # Black
BIRed='\033[1;91m'        # Red
BIGreen='\033[1;92m'      # Green
BIYellow='\033[1;93m'     # Yellow
BIBlue='\033[1;94m'       # Blue
BIPurple='\033[1;95m'     # Purple
BICyan='\033[1;96m'       # Cyan
BIWhite='\033[1;97m'      # White

# High Intensity backgrounds
On_IBlack='\033[0;100m'   # Black
On_IRed='\033[0;101m'     # Red
On_IGreen='\033[0;102m'   # Green
On_IYellow='\033[0;103m'  # Yellow
On_IBlue='\033[0;104m'    # Blue
On_IPurple='\033[0;105m'  # Purple
On_ICyan='\033[0;106m'    # Cyan
On_IWhite='\033[0;107m'   # White
NOCCOLOR='\033[0m'

#available status codes
status_enum="ok|FAIL|ERROR|SKIP|MISSING|NOT_RUNNING|CRASHED"

DAOS_BIN=''
if [[ -e $DAOS_PATH/install/bin/dmg ]]; then
    DAOS_BIN="$DAOS_PATH/install/bin/"
fi
if [[ -e $DAOS_PATH/bin/dmg ]]; then
    DAOS_BIN="$DAOS_PATH/bin/"
fi
if [[ $DAOS_BIN == '' ]]; then
    echo "dmg was not found in the usual places, exiting"
    exit 1
fi

declare -a status
declare -a stop
assign_status()
{
    local -n assocArrayRef=$2
    local input="|$status_enum|"
    local OLD_IFS=$IFS
    IFS=,
    for el in $1; do
        local found=`echo $input | grep "|$el|"`
        if [[ ! $found == $input ]];
        then
            echo "Status $el not recognized, use one or more of $status_enum separated by commas"
            exit 1
        fi
        $2 $el
    done
    IFS=$OLD_IFS
}

add_status()
{
    local count=${#status[@]}
    status[$count]=$1
}

add_stop()
{
    # local count=${#stop[@]}
    stop[$1]=$1
}

summary=0
skipped=0
start_count=0
end_count=1000000
restart_count=0
clean_daos=0
while (( $# ))
    do
        case $1 in
            summary)
                summary=1
                echo "summarize results without running tests"
                ;;
            status)
                assign_status $2 add_status
                shift
                ;;
            stop)
                assign_status $2 add_stop
                shift
                ;;
            cleandaos)
                clean_daos=1
                ;;
            restart)
                restart_count=$2
                shift
                ;;
            start)
                start_count=$2
                shift
                ;;
            end)
                end_count=$2
                shift
                ;;
            verbose)
                set -x
                ;;
            *)
                echo "Unknown option $1"
                exit 1
                ;;
        esac
        shift
    done

input="test_list.txt"
csv_output="test_output.csv"
declare -A result_summary
csv_summary="test_summary.csv"
csv_diff="test_diff.csv"
test_count=0
failed=0
working_folder=`pwd`

if [[ ! -e $input ]];
then
    echo "Creating lists file: $input"
    S3TEST_CONF=s3tests.conf virtualenv/bin/nosetests -v --collect-only 2> $input
fi

echo "Test name,Results,Count,Time" > $csv_output

check_run_results()
{
    if [[ -e $1 ]];
    then
        # trim empty lines, get the last line
        grep "." $1 | tail -n 1
    else
        echo 'MISSING'
    fi
}

extract_test_count()
{
    # Ran 0 tests in 303.605s
    # Ran 1 test in 23.321s
    local testcount=''
    if [[ -e $1 ]];
    then
        local grep_out=`grep 'Ran [0-9]* tests* in [0-9\.s]*' $1`
        testcount=`echo $grep_out | sed -E 's/Ran ([0-9]*) tests* in ([0-9\.s]*)/\1,\2/'`
    fi
    if [[ $testcount == '' ]];
    then
        testcount='MISSING,MISSING'
    fi
    echo $testcount
}

check_test_result()
{
    if [[ -e $1 ]];
    then
        local test_status=`grep '\.\.\.' $1`
        local result=`echo $test_status | sed -E 's/(^.*) \.\.\. (.*$)/\2/'`
        if [[ $result == '' ]];
        then
            # no results found, check the last line of the file for a status
            # result=$(check_run_results $1)
            result='MISSING'
        else
            if [[ $result =~ ' ' ]];
            then
                # the debug output is getting in the way of the status.
                # Find the first status_enum followed by EOL
                local grep_pattern=`echo "$status_enum\$" | sed 's/|/\$\\|/g' `
                result=`grep -o -e "$grep_pattern" $1`
                if [[ $result == '' ]];
                then
                    result='MISSING'
                fi
            fi
        fi
        echo $result
    else
        echo 'MISSING'
    fi
}

isRadosgwRunning()
{
    if [ $summary == 1 ];
    then
        # if summarizing, we don't care if its running
        return 1
    fi
    local pid_path="$CEPH_PATH/build/out/radosgw.8000.pid"
    if [[ -e $pid_path ]];
    then
        local RADOSGW_PID=`cat $pid_path`
        local RADOSGW_RUNNING=`ps $RADOSGW_PID | grep -o $RADOSGW_PID`
        if [[ $RADOSGW_RUNNING == $RADOSGW_PID ]];
        then
            return 1
        fi
    fi
    return 0
}

function wait_for()
{
    timeout=0
    searchterms=$1
    $2 &> /tmp/dmg.log
    while true
    do
        for search in "${searchterms[@]}"
        do
            grepresult=`grep -q "$search" < /tmp/dmg.log`
            if $grepresult ; then
                return
            fi
        done
        if [[ ! "$3" == "" ]] && [ $timeout -ge $3 ]; then
            echo "Timeout occurred waiting for [ ${searchterms[@]} ] in /tmp/dmg.log"
            cat /tmp/dmg.log
            exit 1
        fi
        sleep 1
        ((timeout++))
        $2 &> /tmp/dmg.log
    done
}

restart_daos()
{
    # sh run_tests.sh cleandaos restart 50
    query_system="sudo ${DAOS_BIN}dmg system query"
    sudo ${DAOS_BIN}dmg system stop
    match=( "Stopped" "storage format required" )
    wait_for $match "$query_system" 10
    sudo ${DAOS_BIN}dmg system erase
    match=( "storage format required" )
    wait_for $match "$query_system" 10
    sleep 10
    sudo ${DAOS_BIN}dmg storage format --force
    sleep 10
    sudo ${DAOS_BIN}dmg pool create --size=4GB tank
    sleep 10
}

attempt_restart()
{
    if [ $summary == 0 ];
    then
        index=1
        rados_restart=5
        while [ $index -le $rados_restart ]; do
            ((index++))
            echo "attempt to retart radosgw"
            pushd ${CEPH_PATH}/build
            sudo ../src/stop.sh
            sudo rm -rf ${CEPH_PATH}/build/out/* /tmp/*
            if [ $clean_daos -ne 0 ]; then
                restart_daos
            fi
            sudo RGW=1 ../src/vstart.sh -d
            popd
            sh setup.sh
            if [[ $? == 0 ]]; then return; fi
        done
        echo "Failed to restart radosgw after $rados_restart attempts"
        exit 1
    fi
}

isTestScheduledToRun()
{
    # check if the count is in range of the requested tests
    if [ $test_count -lt $start_count ] || [ $test_count -gt $end_count ];
    then
        return 0
    fi
    # check if the requested status is empty or the status matches the requested status
    if [ ${#status[@]} -eq 0 ] || [[ " ${status[@]} " =~ " ${testresult} " ]];
    then
        return 1
    fi
    return 0
}

checkRestartNeeded()
{
    if [ $summary -eq 0 ] && [ $restart_count -gt 0 ]; then
        local execution_count=$(($test_count-$skipped-1))
        local mod=$(expr $execution_count % $restart_count)
        if [ $execution_count -gt 0 ] && [ $mod -eq 0 ]; then
            attempt_restart
            echo "Restarted radosgw..."
        fi
    fi
}

get_status_color()
{
    case $1 in
    ok)
        echo $BIGreen
        ;;
    FAIL)
        echo $BIPurple
        ;;
    ERROR)
        echo $BIBlue
        ;;
    SKIP)
        echo $BICyan
        ;;
    MISSING)
        echo $On_IBlue
        ;;
    NOT_RUNNING)
        echo $On_IYellow
        ;;
    CRASHED)
        echo $On_IRed
        ;;
    *)
        echo $NOCCOLOR
        ;;
    esac
}

get_count_color()
{
    case $1 in
    0)
        echo $On_IRed
        ;;
    MISSING)
        echo $On_IRed
        ;;
    *)
        echo $BIGreen
        ;;
    esac
}

get_execution_time_color()
{
    local exec_time=`echo $1 | sed "s/^\([0-9]*\).*$/\1/"`

    if [[ $1 == 'MISSING' ]] || [ $exec_time -gt 120 ]; then
        echo $On_IRed
    else
        echo $BIGreen
    fi
}

run_test()
{
    testname=$1
    testfile=$2
    # replace the last period with a colon
    testcommand=`echo "$testname" | sed -r "s/(.*)\.([^\.]+)/\1:\2/"`
    testresult=''
    testresult=$(check_test_result $testfile)
    checkRestartNeeded
    echo "count=$test_count skipped=$skipped $testname"
    isRadosgwRunning
    if [[ $? == 1 ]];
    then
        isTestScheduledToRun
        if [[ $? == 1 ]];
        then
            if [ $summary == 0 ];
            then
                echo "S3TEST_CONF=s3tests.conf virtualenv/bin/nosetests -v $testcommand" > $testfile
                S3TEST_CONF=s3tests.conf virtualenv/bin/nosetests -v $testcommand 2>> $testfile
            else
                ((skipped++))
            fi
            testresult=''
            isRadosgwRunning
            if [[ $? == 1 ]];
            then
                testresult=$(check_test_result $testfile)
                if [[ ! $testresult == 'ok' ]];
                then
                    ((failed++))
                fi
            else
                attempt_restart
                testresult='CRASHED'
                ((failed++))
                echo "$testname ... $testresult" >> $testfile
            fi
        else
            ((skipped++))
        fi
    else
        if [[ ! $testresult == 'ok' ]];
        then
            echo "S3TEST_CONF=s3tests.conf virtualenv/bin/nosetests -v $testcommand" >> $testfile
            echo "$testname ... NOT_RUNNING" >> $testfile
        fi
        attempt_restart
        testresult='NOT_RUNNING'
        ((skipped++))
    fi
    if [[ $testresult == '' ]];
    then
        echo "Test failed - testresult should never be empty: $testfile"
        exit 1
    fi
    count_time=$(extract_test_count $testfile)
    RESULTCOLOR=$(get_status_color $testresult)
    execution_time=`echo $count_time | sed "s/^.*,\(.*\)$/\1/"`
    EXECUTIONTIMECOLOR=$(get_execution_time_color $execution_time)
    execution_count=`echo $count_time | sed "s/^\(.*\),.*$/\1/"`
    COUNTCOLOR=$(get_count_color $execution_count)

    echo -e " ${COUNTCOLOR}count=$execution_count$NOCCOLOR ${EXECUTIONTIMECOLOR}time=$execution_time$NOCCOLOR ${RESULTCOLOR}result=$testresult$NOCCOLOR $testfile"
    if [[ $count_time == '' ]];
    then
        echo "Test failed - count_time should never be empty: $testfile"
        exit 1
    fi
    echo "$testname,$testresult,$count_time" >> $csv_output
    ((result_summary[$testresult]++))

    # check for a stop status
    if [ ${#stop[@]} -ne 0 ] && [[ " ${stop[@]} " =~ " ${testresult} " ]]; then
        echo "stop status $testresult found, stopping, summarizing..."
        summarize
        exit 1
    fi
}

get_test_filename()
{
    echo "test_results/${1}.txt"
}

if [[ ! -d test_results ]];
then
    mkdir test_results
fi

create_test_array()
{
    local counter=0
    while IFS= read -r line
    do
        if [[ $line =~ ok$ ]];
        then
            if [[ ! $line =~ \(.*\) ]];
            then
                # strip the space... to the end of the line
                local testname=`echo "$line" | sed -e "s/ .*$//"`
                test_list[$counter]=${testname}
                ((counter++))
            fi
        fi
    done < "$1"
}

test_one()
{
    local test_file=$(get_test_filename $1)
    ((test_count++))
    run_test $1 $test_file
}

test_each()
{
    for test_name in "${test_list[@]}"
    do
        test_one ${test_name}
    done
}

old_summarize()
{
    echo "Result,Count,Percentage" > $csv_summary
    local total_tests=${#test_list[@]}
    for resultkey in "${!result_summary[@]}"
    do
        local percentage=$(expr ${result_summary[$resultkey]} \* 100 / $total_tests)
        echo "$resultkey,${result_summary[$resultkey]},$percentage%" >> $csv_summary
    done
}

summarize()
{
    local total_tests=${#test_list[@]}
    local summary_title="Date|Host|$status_enum|Total"
    local csv_line=''
    local csv_title=`echo $summary_title | sed 's/|/,/g'`
    echo $csv_title > $csv_summary
    OLD_IFS=$IFS
    IFS=,
    for el in $csv_title; do
        case $el in
            Date)
                csv_line=`date +%m-%d-%Y`
                ;;
            Total)
                csv_line="$csv_line,$total_tests"
                ;;
            Host)
                csv_line="$csv_line,$HOSTNAME"
                ;;
            *)
                local result_count=${result_summary[$el]}
                if [[ $result_count == '' ]];
                then
                    result_count=0
                fi
                local math_calc="$result_count * 100 / $total_tests"
                local percentage=`bc <<< "scale=1; $math_calc"`
                csv_line="$csv_line,$result_count/$percentage%"
                ;;
        esac
    done
    IFS=$OLD_IFS
    echo "$csv_line" >> $csv_summary
    # trim the Time column off so diffs are possible
    sed -e 's/,[0-9\.]*s$//' < $csv_output > $csv_diff
}

run_all_tests()
{
    create_test_array $input
    test_each

    echo "Execution completed with $failed tests failing"
    summarize
}
run_all_tests
