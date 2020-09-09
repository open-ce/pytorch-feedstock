#!/bin/bash

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


OMP_NUM_THREADS=16
export OMP_NUM_THREADS

TORCH_CUDA_ARCH_LIST="__ARCHLIST__"
export TORCH_CUDA_ARCH_LIST

