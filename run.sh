#!/bin/bash
STARTTIME=$(date +%s)
output=
debug=false
makeproj=true

SCRIPT_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)
TEST_DIR=$SCRIPT_DIR/operator-tests
export TEST_DIR

function help() {
    echo "usage: run.sh [-h] [-f FILE] [regexp]"
    echo
    echo "Run tests in subdirectories under $TEST_DIR."
    echo
    echo "If there is a current openshift login, set the project to the name of each subdirectory"
    echo "under $TEST_DIR before running tests in that subdirectory unless -p is set."
    echo
    echo "Options:"
    echo "  -h       Print this help message"
    echo "  -f FILE  Redirect all output to FILE"
    echo "  -d       Debug, set -x (large amount of output)"
    echo "  -p       Do not create a new project per test directory"
    echo
    echo "Optional arguments:"
    echo "  regexp   Only run test files whose absolute path matches regexp"
    echo
}

while getopts dphf: option; do
    case $option in
        h)
            help
            exit 0
            ;;
	f)
	    output=$OPTARG
	    ;;
        d)
            debug=true
            ;;
        p)
            makeproj=false
            ;;
        *)
            ;;
    esac
done
shift $((OPTIND-1))

if [ -n "$output" ]; then
    exec > ${output}
    exec 2>&1
fi

if [ "$debug" == "true" ]; then
    set -x
fi

# Sourcing common will source test/lib/init.sh
source $TEST_DIR/common
source $SCRIPT_DIR/util

# Track whether we have a valid oc login
check_ocp

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


if [ "$makeproj" == "true" ]; then
    set_curr_project
fi

failed_list=""
failed=false
dirs=($(find "${TEST_DIR}" -mindepth 1 -type d -not -path "./resources*"))
for dir in "${dirs[@]}"; do

    failed_dir=false

    # Get the list of test files in the current directory
    set +e
    output=$(find_tests $dir ${1:-.*})
    res=$?
    set -e
    if [ "$res" -ne 0 ]; then
        echo $output
        continue
    else
        output=$(echo $output | xargs -n1 | sort)
    fi

    # Turn the list of tests into an array and check the length, skip if zero
    tests=($(echo "$output"))
    if [ "${#tests[@]}" -eq 0 ]; then
        continue
    fi

    echo "++++++ ${dir}"
    if [ "$makeproj" == "true" ]; then
        go_to_project $(basename $dir)
    fi

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

if [ "$makeproj" == "true" ]; then
    restore_curr_project
fi

if [ "$failed" == true ]; then
    echo "One or more tests failed:"
    echo -e $failed_list'\n'
    exit 1
fi
