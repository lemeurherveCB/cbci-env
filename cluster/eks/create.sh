#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")/../.."


# TODO: keep?
account=$(aws sts get-caller-identity --query Account --output text)
region=$(aws configure get region)
export AWS_REGION="${region}"

# TODO: set cbOwner
cbOwner="todo"
AWS_TAGS="Key=cb:user,Value=${USER} Key=cb:owner,Value=${cbOwner} Key=cb:environment,Value=development"
EKSCTL_TAGS="cb:user=${USER},cb:owner=${cbOwner},cb:environment=development"


# export AWS_PAGER=
# aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${REPO}"
# for image in core-oc core-mm agent core-oc-fips core-mm-fips agent-fips; do \
#   aws ecr create-repository --repository-name cloudbees/$image --region "${AWS_REGION}" || echo already exists; \
# done

# # Build images
# PLATFORM=linux/amd64 IMAGE_PREFIX=${REPO}/cloudbees IMAGE_TAG=${CLUSTER} IMAGE_PUSH=true ./offline/build

mkdir -p tmp
# https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller
AWS_LOAD_BALANCER_CHART_VERSION=1.4.8
AWS_LOAD_BALANCER_APP_VERSION=$(helm show chart --repo https://aws.github.io/eks-charts aws-load-balancer-controller --version=$AWS_LOAD_BALANCER_CHART_VERSION | yq '.appVersion')
# Create AWS IAM Policy to allow AWS Load Balancer controller to manage AWS resources
curl -o tmp/iam-policy.json "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${AWS_LOAD_BALANCER_APP_VERSION}/docs/install/iam_policy.json"
aws iam create-policy --policy-name "AWSLoadBalancerControllerIAMPolicy-${CLUSTER}" --policy-document file://tmp/iam-policy.json

# Create cluster
KUBERNETES_VERSION="'1.28'"
sed "s/@CLUSTER_NAME@/${CLUSTER}/g; s/@KUBERNETES_VERSION@/${KUBERNETES_VERSION}/g; s/@REGION@/${AWS_REGION}/g; s/@ACCOUNT@/${ACCOUNT}/g" < cluster/eks/cluster.yaml > "tmp/${CLUSTER}-cluster.yaml"
eksctl create cluster -f "tmp/${CLUSTER}-cluster.yaml"
echo "=====> To clean up: make eks-delete CLUSTER=${CLUSTER}"

# Configure gp3 instead of gp2
kubectl apply -f cluster/eks/sc-gp3.yaml
kubectl annotate sc/gp2 storageclass.kubernetes.io/is-default-class-

# Install AWS Load Balancer controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
helm install \
  --repo https://aws.github.io/eks-charts aws-load-balancer-controller \
  -n kube-system aws-load-balancer-controller \
  --version ${AWS_LOAD_BALANCER_CHART_VERSION} \
  -f cluster/eks/aws-load-balancer-controller-values.yaml \
  --set "clusterName=${CLUSTER}"
kubectl rollout status --namespace kube-system deployment aws-load-balancer-controller --timeout=5m
kubectl create namespace "${CLUSTER}"
kubectl config set-context --current "--namespace=${CLUSTER}"

hostName="$HOST_NAME"
if ! [ -v hostName ]; then
  helm install --wait alb-placeholder cluster/eks/alb-placeholder --set name="${CLUSTER}" --set namespace="${CLUSTER}"
  alb_hostname=
  while [ -z "$alb_hostname" ]
  do
    alb_hostname=$(kubectl get ingress echoserver -o go-template='{{ range .status.loadBalancer.ingress }}{{ .hostname}}{{"\n"}}{{end}}')
  done
else
  alb_hostname=$hostName
fi
echo "$alb_hostname" >host
cat >>clean-up.sh <<EOF
rm host
EOF

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
aws iam create-policy \
  --policy-name "external-dns-$CLUSTER" \
  --policy-document file:///tmp/external-dns-policy.json \
  --tags $AWS_TAGS
cat >>clean-up.sh <<EOF
aws iam delete-policy --policy-arn arn:aws:iam::$account:policy/external-dns-$CLUSTER
EOF
eksctl create iamserviceaccount \
  --cluster=$CLUSTER \
  --namespace=kube-system \
  --name=external-dns \
  --role-name=external-dns-$CLUSTER \
  --attach-policy-arn=arn:aws:iam::$account:policy/external-dns-$CLUSTER \
  --approve \
  --tags "$EKSCTL_TAGS"
helm upgrade \
  --install \
  --repo https://kubernetes-sigs.github.io/external-dns/ \
  external-dns \
  external-dns \
  --namespace kube-system \
  -f cluster/eks/external-dns-values.yaml

ATH_ARG=""
if $ATH; then
  ATH_ARG="--values cluster/${IP_FAMILY}/values-ath.yaml"
fi

helm install casc cluster/casc --wait

# shellcheck disable=SC2086
helm install \
  --repo https://public-charts.artifacts.cloudbees.com/repository/public/ cloudbees
  ${ATH_ARG} \
  --set OperationsCenter.HostName="$alb_hostname" \
  -f cluster/eks/values.yaml \
  "${CLUSTER}" \
  cloudbees/cloudbees-core \
  --wait
echo "browse: http://${alb_hostname}/cjoc/"
echo "use the following password:"
kubectl exec cjoc-0 -- cat /var/login/password

./postinstall.sh
