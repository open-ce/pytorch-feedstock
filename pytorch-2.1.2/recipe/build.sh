#!/usr/bin/env bash
# *****************************************************************
# (C) Copyright IBM Corp. 2019, 2023. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************
set -ex

if [[ $ppc_arch == "p10" ]]
then
  if [[ -z "${GCC_HOME}" ]];
  then
    echo "Please set GCC_HOME to the install path of gcc-toolset-12"
    exit 1
  else
    export PATH=${GCC_HOME}/bin/:$PATH
    rm ${PREFIX}/lib/libstdc++.so*
    rm ${BUILD_PREFIX}/lib/libstdc++.so*
  fi
  export CXXFLAGS="${CXXFLAGS} -mcpu=${cpu_opt_arch} -mtune=${cpu_opt_tune}"
  export CFLAGS="${CFLAGS} -mcpu=${cpu_opt_arch} -mtune=${cpu_opt_tune}"
fi

SCRIPT_DIR=$RECIPE_DIR/../../scripts

CUDA_VERSION="${cudatoolkit%.*}"

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

# needed so cmake can find the conda version of librt.so and other libraries and headers
export CMAKE_PREFIX_PATH="${BUILD_PREFIX}/${HOST}/sysroot/usr/;${PREFIX}"

#fplt is needed to fix compiler errors with GCC11
export CXXFLAGS="${CXXFLAGS} -fplt"
export CFLAGS="${CFLAGS} -fplt"

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
export USE_NINJA=0
export USE_MPI=0
export USE_OPENMP=1
export USE_TBB=0

export BUILD_CUSTOM_PROTOBUF=OFF
export BUILD_CAFFE2=1

export PYTORCH_BUILD_VERSION=${PKG_VERSION}
export PYTORCH_BUILD_NUMBER=0

ARCH=`uname -p`

function apply_trt_patches() {
  # update onnx-tensorrt submodule
  cd third_party/onnx-tensorrt
  if [[ $cudatoolkit == '11.0' ]]; then
      git checkout eb559b6cdd1ec2169d64c0112fab9b564d8d503b   #corresponds to TRT 7.2
      cd ../..
      # apply fix for GLIBC
      if [[ "${ARCH}" == 'x86_64' ]]; then
          git apply ${RECIPE_DIR}/0300-onnx-tensorrt-Fix-for-GLIBC_2.14_TRT72.patch
      fi
  elif [[ $cudatoolkit == '10.2' ]]; then
      git checkout 84b5be1d6fc03564f2c0dba85a2ee75bad242c2e   #corresponds to TRT 7.0
      cd ../..
      if [[ "${ARCH}" == 'x86_64' ]]; then
          # apply fix for GLIBC
          git apply ${RECIPE_DIR}/0300-onnx-tensorrt-Fix-for-GLIBC_2.14_TRT70.patch
      fi
  fi
}

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
  
  ## Use centralized CUDA capability settings
  export TORCH_CUDA_ARCH_LIST="${cuda_levels//,/;}"      #PyTorch expects ';' separated arch list
  export TORCH_NVCC_FLAGS="-Xfatbin -compress-all"

  export CMAKE_CUDA_HOST_COMPILER=$CC
  export CMAKE_CUDA_COMPILER=${CUDA_HOME}/bin/nvcc

  # Create symlinks of cublas headers into CONDA_PREFIX
  mkdir -p $CONDA_PREFIX/include
  find /usr/include -name cublas*.h -exec ln -s "{}" "$CONDA_PREFIX/include/" ';'
  export CXXFLAGS="${CXXFLAGS} -I${PREFIX}/include -I${CUDA_HOME}/include -I${CONDA_PREFIX}/include"

  # Temporarily disable TensorRT
  #if [[ $PY_VER < 3.9 ]]
  #then
  #  export USE_TENSORRT=1
  #  apply_trt_patches
  #else
  export USE_TENSORRT=0
  #fi
fi

# use v1.10.2 for onnx submodule
#cd third_party/onnx
#git checkout da889e6b95750350726d149bf447bf0cd1245964
#cd ../..

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
