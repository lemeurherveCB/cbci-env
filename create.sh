#!/bin/bash
set -euxo pipefail

for command in aws eksctl helm curl kubectl; do
  if ! command -v "${command}" &> /dev/null; then
    echo "${command} is not installed. Please install ${command}."
    exit 1
  fi
done

PREFIX="${PREFIX:-pentest}"
CLUSTER="${CLUSTER:-$PREFIX-$RANDOM}"
HOSTED_ZONE="${HOSTED_ZONE:-env.beescloud.com}"
HOST_NAME="${CLUSTER}.${HOSTED_ZONE}"
AWS_REGION="us-east-1"
KUBERNETES_VERSION="'1.28'"

aws sso login --profile cloudbees-cloud-platform-dev
export AWS_PROFILE=cloudbees-cloud-platform-dev

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

cbOwner="todo"
AWS_TAGS="Key=cb:user,Value=${USER} Key=cb:owner,Value=${cbOwner} Key=cb:environment,Value=development"
EKSCTL_TAGS="cb:user=${USER},cb:owner=${cbOwner},cb:environment=development"

mkdir -p tmp
# https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller
AWS_LOAD_BALANCER_CHART_VERSION=1.4.8
AWS_LOAD_BALANCER_APP_VERSION=$(helm show chart --repo https://aws.github.io/eks-charts aws-load-balancer-controller --version="${AWS_LOAD_BALANCER_CHART_VERSION}" | yq '.appVersion')
# Create AWS IAM Policy to allow AWS Load Balancer controller to manage AWS resources if it doesn't exist
if ! aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT}:policy/AWSLoadBalancerControllerIAMPolicy-${CLUSTER}" >/dev/null 2>&1; then
  curl --silent --fail --output tmp/iam-policy.json --location "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${AWS_LOAD_BALANCER_APP_VERSION}/docs/install/iam_policy.json"
  aws iam create-policy --policy-name "AWSLoadBalancerControllerIAMPolicy-${CLUSTER}" --policy-document file://tmp/iam-policy.json --output text
fi

# Create cluster if there isn't already a cluster configuration file with the same name
if [ ! -f "tmp/${CLUSTER}-cluster.yaml" ]; then
  sed "s/@CLUSTER_NAME@/${CLUSTER}/g; s/@KUBERNETES_VERSION@/${KUBERNETES_VERSION}/g; s/@REGION@/${AWS_REGION}/g; s/@ACCOUNT@/${ACCOUNT}/g" < cluster.yaml > "tmp/${CLUSTER}-cluster.yaml"
  eksctl create cluster -f "tmp/${CLUSTER}-cluster.yaml"
fi

# Install AWS Load Balancer controller
helm upgrade --install \
  --repo https://aws.github.io/eks-charts \
  --namespace kube-system \
  --version ${AWS_LOAD_BALANCER_CHART_VERSION} \
  --values aws-load-balancer-controller-values.yaml \
  --set "clusterName=${CLUSTER}" \
  aws-load-balancer-controller \
  aws-load-balancer-controller

kubectl rollout status --namespace kube-system deployment aws-load-balancer-controller --timeout=5m

cat >/tmp/external-dns-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

if ! aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT}:policy/external-dns-${CLUSTER}" >/dev/null 2>&1; then
  aws iam create-policy \
    --policy-name "external-dns-${CLUSTER}" \
    --policy-document file:///tmp/external-dns-policy.json \
    --output text
fi

eksctl create iamserviceaccount \
  --cluster="${CLUSTER}" \
  --namespace=kube-system \
  --name=external-dns \
  --role-name="external-dns-${CLUSTER}" \
  --attach-policy-arn="arn:aws:iam::${ACCOUNT}:policy/external-dns-${CLUSTER}" \
  --approve \
  --tags "${EKSCTL_TAGS}"

helm upgrade --install \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  --namespace kube-system \
  --values external-dns-values.yaml \
  external-dns \
  external-dns

if ! kubectl get namespace cloudbees-core &> /dev/null; then
  kubectl create namespace cloudbees-core
fi
kubectl config set-context --current --namespace=cloudbees-core

helm upgrade --install --namespace cloudbees-core casc casc

helm repo add cloudbees https://public-charts.artifacts.cloudbees.com/repository/public/
helm upgrade --install \
  --values values.yaml \
  --set OperationsCenter.HostName="$HOST_NAME" \
  --wait \
  cloudbees-core \
  cloudbees/cloudbees-core \

kubectl get event --watch &
eventPid=$!
trap "kill ${eventPid}" EXIT
kubectl rollout status --timeout=10m sts cjoc
echo "Browse http://${HOST_NAME}/cjoc/ (after a few minutes to let DNS propagates)"
echo "Use the following password:"
kubectl exec cjoc-0 -- cat /var/login/password
