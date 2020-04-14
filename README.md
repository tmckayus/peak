# peak test runner framework

This test runner is based on the radanalyticsio openshift-test-kit
repository, which in turn is taken from a library of bash test functions
at https://github.com/openshift/origin/tree/master/hack/lib.

In a nutshell, the test functions allow you to execute a command
from a bash shell and then check the status and/or output. You
can also wait for a particular result with a timeout. This provides
a very flexible foundation for testing any application that can
be managed from a CLI.

The peak repository includes it's own custom *setup.sh* and *run.sh*
scripts tailored for testing OpenShift operators and/or OpenShift
applications launched from templates or manifests. However, it
can also be used as a general test runner for things outside
of OpenShift -- if there is no current OpenShift login, it will not
attempt to execute any OpenShift setup commands.

It also is designed to pull in tests for specified git repositories,
so that tests for particular operators can be maintained separately.

## initializing the git submodule in the test repository

When you first clone the test repository, you need to do this

```bash
git submodule update --init
```

## setup.sh script

The setup.sh script does several things to set up a test run:

* Installs specified operators for which a package manifest
  can be found in OpenShift. This essentially means that it
  can install any operator visible in OperatorHub at the time
  setup.sh is run (so it is possible to test custom operators
  as well as certified or community operators, etc)
  
* Creates a namespace with the same name as the operator. This
  namespace will be used to run tests.

* Installs operators based on available install mode. Operators
  that can run globally will be installed in openshift-operators,
  operators that must run in a single namespace will run in the
  namespace named for the operator.

* Clones a git repository containing tests for the operator if
  specified. The tests will be stored in a subdirectory under
  *operator-tests* named for the operator.

* Optionally supports a *-d* flag which will cause the specified
  operators to be re-installed and the associated namespaces to
  be recreated. This guarantees a clean test run.

### usage of setup.sh

```bash
setup.sh [-d] OPERATOR_FILE
```

The *-d* flag optionally causes setup.sh to uninstall any specified operators
and delete namespaces named for the operators before re-installing
and re-creating those namespaces.

The *-D* flag optionally causes setup.sh to uninstall any specified operators
and delete namespaces named for the operators, without reinstalling anything.
This is a useful cleanup option to leave a system as you found it. Be careful,
if an operator was already installed before you started, it will be removed!

### OPERATOR_FILE

The operator file contains space-separated tuples, one per line:

```bash
OPERATOR_NAME DISTRIBUTION_CHANNEL [GIT_TEST_REPOSITORY] [GIT_BRANCH]
```

for example

```bash
radanalytics-spark alpha https://github.com/tmckayus/rad-spark-tests v1
```

This tuple would cause setup.sh to do the following:

* Create the *radanalytics-spark* namespace. Delete it first if *-d* is set.

* Install the *radanalytics-spark* operator from the *alpha* channel using the OLM
  Since radanalytics-spark can be installed globally, it will be installed in the
  *openshift-operators* namespace instead of *radanalytics-spark*. Uninstall the
  operator first if *-d* is set.

* Clone the *tmckayus/rad-spark-tests* repository from github into the
  *operator-tests/radanalytics-spark* subdirectory and set the current branch
  to v1 instead of the default branch. The setup.sh script will not overwrite the
  test subdirectory if it exists.

### Notes on OPERATOR_FILE entries

* If a tuple names an operator which cannot be found in OpenShift, *setup.sh* will
  still create the namespace and clone the test repository. This is useful for
  testing things that are not operators (like applications from templates)

* If a tuple names an operator which cannot be found in OpenShift, the channel
  value has no effect

* The git test repository is optional

* The branch value for the test repository is optional. Naming a branch that
  does not exist will cause the clone to fail, and the error will be visible
  in the console.

### Running outside of OpenShift

If there is no current OpenShift login, *setup.sh*

* will not try to install any operators
* will not try to create any namespaces
* WILL clone the test repositories

## operator-tests/run.sh script

The *run.sh* script will run test files ending in *.sh* in subdirectories under
the *operator-tests* directory. The search will be recursive, so test subdirectories
may contain subdirectories.

For each top-level subdirectory, if there there is a current OpenShift login, the script
will set the project to the name of the subdirectory.

Within a particular test subdirectory, files will be executed in alphabetical order.
This can be particularly useful for applications that are not installed as operators --
just make the alphabetically first file in the directory an install script for the application.

### usage

```bash
operator-tests/run.sh [regexp]
```

If *regexp* is supplied, it will be a regular expression filter on the absolute path of
the test files.

## Adding tests

* Create a new test repository somewhere to hold your tests
* Write .sh test files at the top level of the new repository
* Add an entry to the OPERATOR_FILE that lists your operator,
  the distribution channel, and the new test repository
* Rerun setup.sh to add the new test directory in your current
  checkout of peak and install the operator

### TEST_DIR environment variable

The $TEST_DIR environment variable in your test scripts
will point to the directory where *run.sh* is located
(that is, *operator-tests*). This env var can be used
to reference the root of the test hierarchy

### operator-tests/common

The *common* file is used to initialize some general
env vars for the test scripts and intialize the bash
test library itself.

All test files should source *common* like this

```bash
source $TEST_DIR/common
```

Currently common sets two environment variables that
may be used in test scripts

* MY_SCRIPT is the name of the test script that is currently running
* RESOURCE_DIR is the name of a path where temporary files can be put

### sample test repository

https://github.com:tmckayus/simpletest
