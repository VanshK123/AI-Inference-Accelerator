#!/bin/bash
set -e
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# build kernel module
make -C $ROOT_DIR/kernel_module

# build C++ SDK
mkdir -p $ROOT_DIR/sdk/build
pushd $ROOT_DIR/sdk/build
cmake ..
make -j$(nproc)
popd

# build Python bindings with pybind11
if python3 -m venv --help >/dev/null 2>&1; then
    PYTHON=python3
else
    PYTHON=$(which python3)
fi

$PYTHON -m pip install --user pybind11
pushd $ROOT_DIR/sdk/python
$PYTHON setup.py install --prefix=/usr/local
popd
