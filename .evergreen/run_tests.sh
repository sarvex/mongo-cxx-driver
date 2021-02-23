#!/bin/sh

set -o errexit
set -o xtrace
set -o pipefail

export PREFIX=$(pwd)/../mongoc/

# Set up platform-specific flags
case ${PLATFORM} in
    "windows-64")
	PREFIX=$(cygpath -m "$PREFIX")
	export GENERATOR="Visual Studio 15 2017 Win64"
	export POLY_FLAGS="-DBSONCXX_POLY_USE_MNMLSTC=ON"
	export EXTRA_PATH="/cygdrive/c/cmake/bin:/cygdrive/c/Program Files (x86)/Microsoft Visual Studio/2017/Professional/MSBuild/15.0/Bin"
	;;
    "ubuntu-18.04")
	export POLY_FLAGS="-DBSONCXX_POLY_USE_STD_EXPERIMENTAL=ON -DCMAKE_CXX_STANDARD=14"
	export EXTRA_PATH="/opt/cmake/bin"
	;;
    "macos-10.14")
	export POLY_FLAGS="-DBSONCXX_POLY_USE_BOOST=ON"
	export EXTRA_PATH="/Applications/Cmake.app/Contents/bin"
	;;
    *)
	echo "Unsupported architecture ${PLATFORM}"
	;;
esac

export CMAKE="cmake"

# TODO: need to calculate mongoc version from the branch that
# we are on, and stay in lockstep...
# This might be tricky to do, usually this is in the .mci.yml file manually
# Install the C driver
./install_c_driver.sh ${$MONGOC_VERSION|master}

export BUILD_TYPE="Debug"
export MONGOC_PREFIX=${PREFIX}

if ! python -m virtualenv venv 2>/dev/null; then
    /opt/mongodbtoolchain/v3/bin/python3 -m venv venv
fi

cd venv
if [ -f bin/activate ]; then
    . bin/activate
    ./bin/pip install GitPython
elif [ -f Scripts/activate ]; then
    . Scripts/activate
    ./Scripts/pip install GitPython
fi
cd ..

.evergreen/compile.sh -DCMAKE_PREFIX_PATH="$MONGOC_PREFIX" ${cmake_flags} ${poly_flags} -DCMAKE_INSTALL_PREFIX=install

export PATH="${EXTRA_PATH}:$PATH"

# Run tests
export LD_LIBRARY_PATH=.:$PREFIX/lib/
export DYLD_LIBRARY_PATH=.:$PREFIX/lib/
export PATH=$(pwd)/src/bsoncxx/${build_type}:$(pwd)/src/mongocxx/${build_type}:$PREFIX/bin:$(pwd)/install/bin:$PATH

# skip mongocryptd tests, can we?
# TODO refactor these into a shared place where .mci.yml can also use them
export CRUD_TESTS_PATH="$(pwd)/../data/crud"
export CHANGE_STREAM_TESTS_PATH="$(pwd)/../data/change_stream"
#export ENCRYPTION_TESTS_PATH="$(pwd)/../data/client_side_encryption"
export GRIDFS_TESTS_PATH="$(pwd)/../data/gridfs"
export COMMAND_MONITORING_TESTS_PATH="$(pwd)/../data/command-monitoring"
export TRANSACTIONS_TESTS_PATH="$(pwd)/../data/transactions"
export WITH_TRANSACTION_TESTS_PATH="$(pwd)/../data/with_transaction"
export RETRYABLE_READS_TESTS_PATH="$(pwd)/../data/retryable-reads"
export READ_WRITE_CONCERN_OPERATION_TESTS_PATH="$(pwd)/../data/read-write-concern/operation"

if [ "windows" == $PLATFORM ]; then
    CRUD_TESTS_PATH=$(cygpath -m $CRUD_TESTS_PATH)

    CTEST_OUTPUT_ON_FAILURE=1 MSBuild.exe /p:Configuration=Debug RUN_TESTS.vcxproj
    #CTEST_OUTPUT_ON_FAILURE=1 MSBuild.exe /p:Configuration=Debug examples/run-examples.vcxproj
else
    ulimit -c unlimited || true
    ./src/bsoncxx/test/test_bson
    ./src/mongocxx/test/test_driver
    ./src/mongocxx/test/test_change_stream_specs
    #./src/mongocxx/test/test_client_side_encryption_specs
    ./src/mongocxx/test/test_crud_specs
    ./src/mongocxx/test/test_gridfs_specs
    ./src/mongocxx/test/test_command_monitoring_specs
    ./src/mongocxx/test/test_instance
    ./src/mongocxx/test/test_transactions_specs
    ./src/mongocxx/test/test_logging
    ./src/mongocxx/test/test_retryable_reads_specs
    ./src/mongocxx/test/test_read_write_concern_specs
fi

# TODO: what about the URI? How to pass that in?
