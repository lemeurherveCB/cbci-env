#!/usr/bin/env bash
# set -euxo pipefail
set -euo pipefail

DRY_RUN=${DRY_RUN:-true}

# Define the patterns you want to filter
patterns=("hlmp" "hlemeu")

# Function to check if the arg matches any of the patterns
matches_pattern() {
    for pattern in "${patterns[@]}"; do
        if [[ "$1" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# echo "#########################"
# echo "### Deleting clusters ###"
# echo "#########################"

# total=0
# matched=0

# for cluster in $(eksctl get clusters --region us-east-1 --output json | jq -r '.[].Name')
# do
#     total=$((total + 1))
#     if matches_pattern "$cluster"; then
#         matched=$((matched + 1))
#         [ "$DRY_RUN" = true ] && echo "[dry-run] Deleting cluster $cluster" || eksctl delete cluster --disable-nodegroup-eviction --parallel 25 --name $cluster && echo "$cluster deleted."
#     else
#         echo "Not deleting cluster $cluster"
#     fi
# done

# echo "Total: $total"
# echo "Total matched for deletion: $matched"

echo "#########################"
echo "### Deleting policies ###"
echo "#########################"

total=0
matched=0

# Note: be aware that the filter is on the arn, not the name
for policy in $(aws iam list-policies | jq -r '.Policies.[].Arn')
do
    total=$((total + 1))
    if matches_pattern "$policy"; then
        matched=$((matched + 1))
        [ "$DRY_RUN" = true ] && echo "[dry-run] Deleting policy $policy" || aws iam delete-policy --policy-arn $policy && echo "$policy deleted."
    # else
        # echo "Not deleting policy $policy"
    fi
done

echo "Total: $total"
echo "Total matched for deletion: $matched"

# for mountTarget in $(aws iam list-policies json | jq -r '.Policies.[].Arn')
# do
    # echo "Checking policy $mountTarget"
#     if matches_pattern "$mountTarget"; then
#         [ "$DRY_RUN" = true ] && echo "[dry-run] Deleting mountTarget $mountTarget" || aws iam delete-mountTarget --mountTarget-arn $mountTarget
#     else
#         echo "Not deleting mountTarget $mountTarget"
#     fi
# done

echo "################################"
echo "### Deleting security groups ###"
echo "################################"

total=0
matched=0

for securityGroup in $(aws ec2 describe-security-groups | jq -r '.SecurityGroups.[].GroupName')
do
    total=$((total + 1))
    if matches_pattern "$securityGroup"; then
        matched=$((matched + 1))
        [ "$DRY_RUN" = true ] && echo "[dry-run] Deleting securityGroup $securityGroup" || aws ec2 delete-security-group --group-name $securityGroup && echo "$securityGroup deleted."
    else
        echo "Not deleting securityGroup $securityGroup"
    fi
done

echo "Total: $total"
echo "Total matched for deletion: $matched"

# echo "############################"
# echo "### Deleting DNS records ###"
# echo "############################"


# !!!!! TODO !!!!!!!!

# total=0
# matched=0

# for securityGroup in $(aws ec2 describe-security-groups | jq -r '.SecurityGroups.[].GroupName')
# do
#     total=$((total + 1))
#     if matches_pattern "$securityGroup"; then
#         matched=$((matched + 1))
#         [ "$DRY_RUN" = true ] && echo "[dry-run] Deleting securityGroup $securityGroup" || aws ec2 delete-security-group --group-name $securityGroup
#     else
#         echo "Not deleting securityGroup $securityGroup"
#     fi
# done

# echo "Total: $total"
# echo "Total matched for deletion: $matched"

# # TODO delete policy versions as in cbci-eks-dr-demo/teardown.sh
# aws iam delete-policy --policy-arn arn:aws:iam::706501674089:policy/alb-hlmp3-19113
# rm host
# aws iam delete-policy --policy-arn arn:aws:iam::706501674089:policy/external-dns-hlmp3-19113
# for id in $(aws efs describe-mount-targets --file-system-id fs-0c56fae71b77ef5bc --query 'MountTargets[*].MountTargetId' --output text)
# do
#   aws efs delete-mount-target --mount-target-id $id
# done
# until [ -z "$(aws efs describe-mount-targets --file-system-id fs-0c56fae71b77ef5bc --query 'MountTargets[*].MountTargetId' --output text)" ]
# do
#   sleep 5
# done
# aws efs delete-file-system --file-system-id fs-0c56fae71b77ef5bc
# aws ec2 delete-security-group --group-id sg-0b2c9670b597b2987
# rm platform
# for image in core-oc core-mm agent git-daemon
# do
#   docker images --format '{{.Repository}}:{{.Tag}}' 706501674089.dkr.ecr.us-east-1.amazonaws.com/hlmp3-19113/$image | xargs -r docker rmi
#   aws ecr delete-repository --repository-name hlmp3-19113/$image --force
# done
# rm registry push.sh
# rm helm.yaml
# rm ns
