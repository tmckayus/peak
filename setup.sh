#!/bin/bash

function help() {
    echo "usage: setup.sh [-d] FILE"
    echo
    echo "Required:"
    echo "  FILE     a file of 'operatorname channel github' space-separated triplets, one per line"
    echo "           Check the README.md for more information."
    echo
    echo "Options:"
    echo "  -d       delete projects (corresponding to operatorname) to make sure they are clean"
    echo "           before running tests. For operators this will also cause the operator to be"
    echo "           reinstalled"
}

function set_project() {
    if [ "$OCP" -eq 0 ]; then
        orig_project=$(oc project -q)
    fi
}

function restore_project() {
    if [ "$OCP" -eq 0 ]; then
        oc project $orig_project
    fi
}

function delete_operator() {
    if [ "$2" == "true" ]; then
	# we installed this globally in openshift-operators
        namespace=openshift-operators
    else
	namespace=$1
    fi
    set +e
    csv=$(oc get subscription $1 -n $namespace -o=jsonpath="{.status.currentCSV}")
    if [ "$?" -eq 0 ]; then
        oc delete subscription $1 -n $namespace
        oc delete clusterserviceversion $csv -n $namespace
    fi
    set -e
}

function installop() {
    # $1 operator name
    # $2 channel

    # We'll make a namespace from the name because later we'll want to
    # run tests here anyway regardless of whether or not it's an actual
    # operator or something deployed from manifests.

    # The subdirectory holding the git test repo will also be given
    # this name. The test runner will use the directory name as
    # the namespace.

    # Note that in the case of an operator in a single namespace,
    # the operator group and subscription will be created here.

    echo ++++++++++++++ Setting up operator $1 and creating namespace ++++++++++++++

    # If there is a manifest, we can install the operator (and we might have previously)
    installMode=""
    set +e
    oc get packagemanifest $1 &> /dev/null
    manifest_present="$?"
    if [ "$manifest_present" -eq 0 ]; then
        installMode=$(oc get packagemanifest $1 -o=jsonpath="{.status.channels[?(@.name==\"$2\")].currentCSVDesc.installModes[?(@.type==\"AllNamespaces\")].supported}")
    fi
    set -e

    # If delproj is set, delete the namespace and uninstall the operator
    if [ "$delproj" == "true" ]; then
	if [ "$manifest_present" -eq 0 ]; then
	    echo Attempting to uninstall operator $1
	    delete_operator $1 $installMode
        fi
        clean_project $1
    else
        go_to_project $1
    fi

    if [ "$manifest_present" -ne 0 ]; then
        echo operator manifest not present for $1, skipping install
        return
    else
        echo operator manifest found for $1
    fi

    # Look up the specified channel and find the catalog source
    csource=$(oc get packagemanifest $1 -o=jsonpath="{.status.catalogSource}")

    # Look up the specified channel and find the catalog source namespace
    csourcens=$(oc get packagemanifest $1 -o=jsonpath="{.status.catalogSourceNamespace}")

    set +e
    if [ "$installMode" == "true" ]; then
        echo "install $1 in namespace openshift-operators"

        # create a subscription object
        cat <<- EOF | oc create -f -
	apiVersion: operators.coreos.com/v1alpha1
	kind: Subscription
	metadata:
	  name: $1
	  namespace: openshift-operators
	spec:
	  channel: $2
	  name: $1
	  source: $csource
	  sourceNamespace: $csourcens
	EOF

    else
        echo "install $1 in namespace $1"

        # in this case we need to make an operator group in the new project
        cat <<- EOF | oc create -f -
	apiVersion: operators.coreos.com/v1
	kind: OperatorGroup
	metadata:
	  name: "$1"
	  namespace: "$1"
	spec:
	  targetNamespaces:
	  - "$1"
	EOF

        # create a subscription object
        cat <<- EOF | oc create -f -
	apiVersion: operators.coreos.com/v1alpha1
	kind: Subscription
	metadata:
	  name: $1
	  namespace: $1
	spec:
	  channel: $2
	  name: $1
	  source: $csource
	  sourceNamespace: $csourcens
	EOF
    fi
    set -e
}

function addtestdir() {
    if [ ! -d operator-tests/$1 ]; then
	echo ++++++++++++++ Cloning test repository for $1 ++++++++++++++
        if [ -n "$3" ]; then
           echo git clone $2 --branch $3 operator-tests/$1
           git clone $2 --branch $3 operator-tests/$1
        else
           echo git clone $2 operator-tests/$1
           git clone $2 operator-tests/$1
        fi
    fi
}

################ Main script ################

# Track whether we have a valid oc login
source operator-tests/util
check_ocp

delproj=false
while getopts dh option; do
    case $option in
        d)
            delproj=true
            ;;
        h)
            help
            exit 0
            ;;
        *)
           ;;
    esac
done
shift $((OPTIND-1))
if [ "$#" -lt 1 ]; then
    help
    exit 0
fi

set_curr_project
while IFS= read -r line
do
  vals=($line)

  if [ "${#vals[@]}" -lt 2 ]; then
      echo "Invalid tuple '${vals[@]}' in $1, skipping"
      continue
  fi

  # If we have an oc login, install the operators
  if [ "$OCP" -eq 0 ]; then
      installop ${vals[@]:0:2}
  fi

  # clone a specific repository for tests if one is listed
  branch=""
  if [ "${#vals[@]}" -gt 2 ]; then
      if [ "${#vals[@]}" -gt 3 ]; then
          branch=${vals[3]}
      fi
      addtestdir ${vals[0]} ${vals[2]} $branch
  fi
done < "$1"
restore_curr_project
