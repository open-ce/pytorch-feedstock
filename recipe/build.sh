#!/usr/bin/env bash
# *****************************************************************
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2019, 2020. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
# *****************************************************************
set -ex

SCRIPT_DIR=$RECIPE_DIR/../scripts

# Anaconda pre-seeds CFLAGS and CXXFLAGS with preferred settings.
# Among those for C++ is "-std=c++17". In CMakeLists.txt the standard
# is set to c++11, using any other value introduces compile failures.
# Here we will remove the Anaconda seeded std from CXXFLAGS which will
# allow cmake to add the std as requested based on the project settings.
export CXXFLAGS="$(echo ${CXXFLAGS} | sed -e 's/ -std=[^ ]*//')"
export CXXFLAGS="${CXXFLAGS} -D__STDC_FORMAT_MACROS"

# remove the --as-needed flag it will be replaced in CMakeList.txt
export LDFLAGS="$(echo ${LDFLAGS} | sed -e 's/-Wl\,--as-needed//')"
export LDFLAGS="${LDFLAGS} -Wl,-rpath-link,${PREFIX}/lib"

if [[ $build_type == "cpu" ]]
then
  # Disable GPU-related libraries
  export USE_CUDA=0
  export USE_CUDNN=0
  export USE_TENSORRT=0

elif [[ $build_type == "cuda" ]]
then
  # Enable GPU-related libraries
  export USE_CUDA=1
  export USE_CUDNN=1
  export USE_TENSORRT=1
else
    echo "build_type was set to '$build_type', an invalid value."
    echo "build_type must be set to either 'cpu' or 'cuda'."
    exit 1
fi

# select OpenBLAS for BLAS
export BLAS=OpenBLAS
export USE_FBGEMM=0
# use system NCCL
export USE_SYSTEM_NCCL=1
# don't use mlkdnn
export USE_MKLDNN=0
# don't use NNPACK/QNNPACK/XNNPACK etc.
export USE_NNPACK=0
export USE_QNNPACK=0
export USE_XNNPACK=0
export USE_PYTORCH_QNNPACK=0

export TH_BINARY_BUILD=1
export USE_LMDB=1
export USE_LEVELDB=1
export USE_OPENMP=1

export BUILD_CUSTOM_PROTOBUF=OFF

if [[ "$USE_CUDA" == 1 ]]; then
    export TORCH_CUDA_ARCH_LIST="3.7;6.0;7.0;7.5"
    export TORCH_NVCC_FLAGS="-Xfatbin -compress-all"
fi

# needed so cmake can find the conda version of librt.so
export CMAKE_PREFIX_PATH="${BUILD_PREFIX}/${HOST}/sysroot/usr/"

# update onnx-tenssorrt submodule
ARCH=`uname -p`
cd third_party/onnx-tensorrt
git checkout 84b5be1d6fc03564f2c0dba85a2ee75bad242c2e
cd ../..
# apply fix for GLIBC
if [[ "${ARCH}" == 'x86_64' ]]; then
  git apply ${RECIPE_DIR}/02-onnx-tensorrt-Fix-for-GLIBC_2.14.patch
fi

# install
MAX_JOBS=${CPU_COUNT} python setup.py install

# remove caffe2 serialized test data files to reduce package size
find ${SP_DIR}/caffe2/python/serialized_test/data -iname "*.zip" -delete

mkdir -p ${PREFIX}/pytorch/doc
cp ${SRC_DIR}/CONTRIBUTING.md ${PREFIX}/pytorch/doc
cp ${SRC_DIR}/README.md ${PREFIX}/pytorch/doc

# Install scripts that set up pytorch environment variables, and adjust the
# TORCH_CUDA_ARCH_LIST setting in the activate script.
mkdir -p "${PREFIX}/etc/conda/activate.d"
mkdir -p "${PREFIX}/etc/conda/deactivate.d"
cp "${SCRIPT_DIR}/pytorch-activate-env-vars.sh"    "${PREFIX}/etc/conda/activate.d"
cp "${SCRIPT_DIR}/pytorch-deactivate-env-vars.sh"  "${PREFIX}/etc/conda/deactivate.d"
sed -i'' -e "s/__ARCHLIST__/$TORCH_CUDA_ARCH_LIST/" "${PREFIX}/etc/conda/activate.d/pytorch-activate-env-vars.sh"
