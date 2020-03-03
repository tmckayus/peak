#!/bin/bash
STARTTIME=$(date +%s)

# Sourcing common will source test/lib/init.sh
TEST_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)
export TEST_DIR
source $TEST_DIR/common
source $TEST_DIR/util

# Track whether we have a valid oc login
check_ocp

function help() {
    echo "usage: run.sh [-h] [regexp]"
    echo
    echo "Run tests in subdirectories under $TEST_DIR."
    echo
    echo "If there is a current openshift login, set the project to the name of each subdirectory"
    echo "under $TEST_DIR before running tests in that subdirectory."
    echo
    echo "Options:"
    echo "  -h       Print this help message"
    echo
    echo "Optional arguments:"
    echo "  regexp   Only run test files whose absolute path matches regexp"
    echo
}

while getopts h option; do
    case $option in
        h)
            help
            exit 0
            ;;
        *)
            ;;
    esac
done
shift $((OPTIND-1))

os::util::environment::setup_time_vars

function cleanup()
{
    out=$?
    set +e

    os::test::junit::reconcile_output

    ENDTIME=$(date +%s); echo "$0 took $(($ENDTIME - $STARTTIME)) seconds"
    os::log::info "Exiting with ${out}"
    exit $out
}

trap "exit" INT TERM
trap "cleanup" EXIT

function find_tests() {
    local test_regex="${2}"
    local full_test_list=()
    local selected_tests=()

    full_test_list=($(find "${1}" -maxdepth 1 -name '*.sh'))
    if [ "${#full_test_list[@]}" -eq 0 ]; then
        return 0
    fi    
    for test in "${full_test_list[@]}"; do
    	test_rel_path=${test#${TEST_DIR}/}
        if grep -q -E "${test_regex}" <<< "${test_rel_path}"; then
            selected_tests+=( "${test}" )
        fi
    done

    if [ "${#selected_tests[@]}" -eq 0 ]; then
        os::log::info "No tests were selected by regex in "${1}
        return 1
    else
        echo "${selected_tests[@]}"
    fi
}

set_curr_project

failed_list=""
failed=false
dirs=($(find "${TEST_DIR}" -mindepth 1 -type d -not -path "./resources*"))
for dir in "${dirs[@]}"; do

    failed_dir=false

    # Get the list of test files in the current directory
    set +e
    output=$(find_tests $dir ${1:-.*} | xargs -n1 | sort)
    res=$?
    set -e
    if [ "$res" -ne 0 ]; then
        echo $output
        continue
    fi

    # Turn the list of tests into an array and check the length, skip if zero
    tests=($(echo "$output"))
    if [ "${#tests[@]}" -eq 0 ]; then
        continue
    fi

    echo "++++++ ${dir}"
    go_to_project $(basename $dir)

    for test in "${tests[@]}"; do
        echo
        echo "++++ ${test}"
        if ! ${test}; then
            echo "failed: ${test}"
            failed=true
            failed_dir=true
            failed_list=$failed_list'\n\t'$test
        fi
    done
done

restore_curr_project

if [ "$failed" == true ]; then
    echo "One or more tests failed:"
    echo -e $failed_list'\n'
    exit 1
fi
