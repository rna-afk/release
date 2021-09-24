#!/bin/bash
CLUSTER_NAME=$(cat ${SHARED_DIR}/CLUSTER_NAME)
for STACK_SUFFIX in compute-2 compute-1 compute-0 control-plane bootstrap proxy security infra vpc
do
    aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-${STACK_SUFFIX}"
done