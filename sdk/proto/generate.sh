#!/bin/bash
#
# This script regenerates all Protobuf/gRPC client files.
#
# For now, it must be run manually, and the results are checked into source control.  Eventually we
# might choose to automate this process as part of the overall build so that it's less manual and
# hence error prone.
#
# This script relies only on Docker. The container holds the installation of gRPC, tools, etc., for
# different langauges, so nothing is else required to be installed on your machine.
set -e

# First build our Protobuf/gRPC compiler Docker image, so dev machines don't need it.
echo "* Building Protobuf/gRPC compilers:"
docker build -t pulumi/protobuf-builder .

DOCKER_RUN="docker run -it --rm -v $(pwd)/../python:/python -v $(pwd)/../nodejs:/nodejs -v $(pwd):/local pulumi/protobuf-builder"
PROTOC="$DOCKER_RUN protoc"

# `status.proto` is in our source tree so that we can implement initialization failure in the
# dynamic client (written in JS) using the protobuf notion of "details" -- arbitrary protobuf
# messages packaged up inside of an error. Hence, `JS_PROTO_FILES` includes it and `PROTO_FILES`
# does not.
PROTO_FILES=$(find . -name "*.proto" -not -name "status.proto")
JS_PROTO_FILES=$(find . -name "*.proto")

echo "* Generating Protobuf/gRPC SDK files:"
echo -e "\tVERSION: $($PROTOC --version)"
echo -e "Generated by version $($PROTOC --version) of protoc" > ./grpc_version.txt

GO_PULUMIRPC=./go
GO_PROTOFLAGS="plugins=grpc"
echo -e "\tGo: $GO_PULUMIRPC [$GO_PROTOFLAGS]"
mkdir -p $GO_PULUMIRPC
$PROTOC --go_out=$GO_PROTOFLAGS:$GO_PULUMIRPC $PROTO_FILES

# Protoc for JavaScript has a bug where it emits Google Closure Compiler directives in the module prologue that mutate
# the global object, which causes side-by-side bugs in pulumi/pulumi (pulumi/pulumi#2401). The protoc compiler
# absolutely should not be emitting commonjs modules that mutate global, but alas, it does, and we have to sed the
# output to not do that.
#
# We're replacing the literal code string
#   var global = Function('return this')();
# with
#   var proto = { pulumirpc: {} }, global = proto;
#
# This sets up the remainder of the protobuf file so that it works fine, but doesn't mess with global.
$DOCKER_RUN /bin/bash -c 'set -x && JS_PULUMIRPC=/nodejs/proto && \
    JS_PROTOFLAGS="import_style=commonjs,binary"    && \
    JS_HACK_PROTOS=$(find . -name "*.proto" -not -name "status.proto") && \
    echo -e "\tJS: $JS_PULUMIRPC [$JS_PROTOFLAGS]"  && \
    TEMP_DIR=/tmp/nodejs-build                      && \
    echo -e "\tJS temp dir: $TEMP_DIR"              && \
    mkdir -p "$TEMP_DIR"                            && \
    protoc --js_out=$JS_PROTOFLAGS:$JS_PULUMIRPC --grpc_out=minimum_node_version=6:$JS_PULUMIRPC --plugin=protoc-gen-grpc=/usr/local/bin/grpc_tools_node_protoc_plugin status.proto && \
    protoc --js_out=$JS_PROTOFLAGS:$TEMP_DIR --grpc_out=minimum_node_version=6:$TEMP_DIR --plugin=protoc-gen-grpc=/usr/local/bin/grpc_tools_node_protoc_plugin $JS_HACK_PROTOS && \
    sed -i "s/^var global = .*;/var proto = { pulumirpc: {} }, global = proto;/" "$TEMP_DIR"/*.js && \
    cp "$TEMP_DIR"/*.js "$JS_PULUMIRPC"'

function on_exit() {
    rm -rf "$TEMP_DIR"
}

# Protoc for Python has a bug where, if your proto files are all in the same directory relative
# to one another, imports of said proto files will produce imports that don't work using Python 3.
#
# Since our proto files are all in the same directory, this little bit of sed rewrites the broken
# imports that protoc produces, of the form
#     import foo_pb2 as bar
# to the form
#     from . import foo_pb2 as bar
# This form is semantically equivalent and is accepted by both Python 2 and Python 3.
trap on_exit EXIT

echo -e "\tPython temp dir: $TEMP_DIR"
$DOCKER_RUN /bin/bash -c 'PY_PULUMIRPC=/python/lib/pulumi/runtime/proto/ && \
    echo -e "\tPython: $PY_PULUMIRPC" && \
    TEMP_DIR="/tmp/python-build" && \
    echo -e "\tPython temp dir: $TEMP_DIR" && \
    mkdir -p "$TEMP_DIR" && \
    python -m grpc_tools.protoc -I./ --python_out="$TEMP_DIR" --grpc_python_out="$TEMP_DIR" *.proto && \
    sed -i "s/^import \([^ ]*\)_pb2 as \([^ ]*\)$/from . import \1_pb2 as \2/" "$TEMP_DIR"/*.py && \
    cp "$TEMP_DIR"/*.py "$PY_PULUMIRPC"'

echo "* Done."
