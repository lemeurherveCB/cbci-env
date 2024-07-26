#!/bin/bash
set -euxo pipefail
cd $(dirname $0)/../..

function warning {
  tput setaf 5
  echo "[WARNING] ${1}"
  tput sgr0
}

function error {
  tput setaf 1
  echo "[ERROR] ${1}"
  tput sgr0
}

eksctl delete cluster --name ${CLUSTER} --disable-nodegroup-eviction --parallel 25  || \
  {
    error "Manual cleanup esential!!"
    error "Please delete stacks at https://${AWS_REGION}.console.amazonaws.com/cloudformation/home?region=us-gov-east-1#/stacks?filteringText=${CLUSTER}&filteringStatus=active&viewNested=true"

    echo -e "\n\n"
    warning "Any EFS and/or EBS volumes created for controllers will need to be cleaned up at: "
    warning "EBS: https://${AWS_REGION}.console.amazonaws.com/ec2/home?region=${AWS_REGION}#Volumes:v=3;search=:=${CLUSTER}"
    warning "EFS: https://${AWS_REGION}.console.amazonaws.com/efs/home?region=${AWS_REGION}#/file-systems"
    exit 13
  }

AWS_PAGER= aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy-${CLUSTER}


echo Cleaning up any dynamically created EBS volumes
readarray -t ebs_volume_ids <  <(aws ec2 describe-volumes --output json --region ${AWS_REGION} --filters "Name=tag:KubernetesCluster,Values=${CLUSTER}" --query Volumes[].VolumeId | jq -r '.[]' )
for volume_id in "${ebs_volume_ids[@]}"; do
    echo "deleting volumeId: $volume_id"
    aws ec2 delete-volume --region ${AWS_REGION} --volume-id $volume_id
done

echo Cleaning up any dynamically created EFS systems
readarray -t efs_filesystem_ids <  <(aws efs describe-file-systems --output json --region ${AWS_REGION} --query "FileSystems[?Tags[?Key=='KubernetesCluster' && Value=='${CLUSTER}']] | [].FileSystemId" | jq -r '.[]' )
for filesystem_id in "${efs_filesystem_ids[@]}"; do
    # we need to delete the mount targets first when using the CLI.
    echo "deleting mount points for filesystem: $filesystem_id"

    readarray -t efs_mount_target_ids < <(aws efs describe-mount-targets --output json --region ${AWS_REGION} --file-system-id $filesystem_id --query 'MountTargets[].MountTargetId' | jq -r '.[]' )
    for mount_target_id in "${efs_mount_target_ids[@]}"; do
      echo "deleteing mount target $mount_target_id"
      aws efs delete-mount-target --region ${AWS_REGION} --mount-target-id $mount_target_id
    done
    # deletion occurs async in the CLI so we need to poll until there are no mount points.
    echo -n waiting for mount targets to be removed...
    while [ $(aws efs describe-mount-targets --output json --region ${AWS_REGION} --file-system-id $filesystem_id --query 'MountTargets | length(@)') != "0" ]; do
      sleep 1s
      echo -n .
    done
    echo

    echo "deleting filesystem: $filesystem_id"
    aws efs delete-file-system --region ${AWS_REGION} --file-system-id $filesystem_id
done
