#!/bin/bash

PORT=$1
NOTEBOOK_DIR=$2
if [ -z "$NOTEBOOK_DIR" ]; then
    cd $SCRATCH
else
    cd $NOTEBOOK_DIR
fi

ml biology system nvtop
ml gdb cmake/3.31.4 gcc/10.1.0
ml cuda/12.4.0  python/3.12.1  py-jupyterlab/4.3.2_py312
export CC=$(which gcc)
export CXX=$(which g++)

source /home/users/chensj16/s/venvs/py12torch2/bin/activate
jupyter lab --no-browser --port=$PORT
