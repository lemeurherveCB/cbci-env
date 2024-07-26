EVALUATION_LICENSE=true
# Whether to set up options suitable for ATH
ATH=false
# Signal we are running in a CI environment
CI=false
# IP family
IP_FAMILY=ipv4
COMMIT_SHA:=$(shell git rev-parse HEAD)

# === Developer targets follow ===

NS:=cbci-test-$(shell bash -c 'echo $${USER:-ci}-$$RANDOM')
ifndef CLUSTER
    CLUSTER:=$(NS)
endif

.PHONY: cluster
cluster:
	@echo $(CLUSTER)

postinstall:
	./postinstall.sh

ifeq ($(EVALUATION_LICENSE),true)
  EVALUATION_LICENSE_ARG=\
    --set OperationsCenter.License.Evaluation.Enabled=true \
    --set OperationsCenter.License.Evaluation.FirstName=$(USER) \
    --set OperationsCenter.License.Evaluation.LastName='of CloudBees' \
    --set OperationsCenter.License.Evaluation.Email=developer@cloudbees.com \
    --set OperationsCenter.License.Evaluation.Company=CloudBees
else
  EVALUATION_LICENSE_ARG=
endif


ACCOUNT=$(shell aws sts get-caller-identity --query 'Account')
eks: AWS_REGION=us-east-1
REPO=$(ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com

eks:
	ATH=$(ATH) IP_FAMILY=$(IP_FAMILY) AWS_REGION=$(AWS_REGION) CLUSTER=$(CLUSTER) REPO=$(REPO) ACCOUNT=$(ACCOUNT) bash cluster/eks/create.sh

eks-delete:
	ACCOUNT=$(ACCOUNT) CLUSTER=$(CLUSTER) bash cluster/eks/delete.sh
