.PHONY: deployments

SHELL := /bin/bash
MAKEFLAGS += --no-print-directory

ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(ARGS):;@:)
DEPLOYMENT=$(PWD)/deployments/$(ARGS)
CONFIG=$(DEPLOYMENT)/eks.yaml
VALUES=$(DEPLOYMENT)/values.yaml
KUBE=$(PWD)/configs/$(ARGS).yaml
KUBECONFIG=KUBECONFIG=$(KUBE)
BOOTSTRAP=$(DEPLOYMENT)/bootstrap.config
JUNO_VERSION=$(shell grep '^version=' ${BOOTSTRAP} | cut -d'=' -f2)
PRIMARY_SUBNET=$(shell grep '^primary_subnet=' ${BOOTSTRAP} | cut -d'=' -f2)
DOMAIN=$(shell grep '^domain=' ${BOOTSTRAP} | cut -d'=' -f2)
SUBNET_SET=--set ingress.config.controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-subnets
HOST_SET=--set genesis.config.host=$(ARGS).$(DOMAIN)

# tools
KUBECTL=$(KUBECONFIG) kubectl
JUNO=$(KUBECONFIG) helm upgrade -i juno ./work/chart/ -f ./values.yaml -f $(VALUES) $(SUBNET_SET)=$(PRIMARY_SUBNET)

# actions
destroy: _validate_environment
	@eksctl delete cluster -n $(ARGS)
	@rm -rf $(KUBE) KUBECONFIG=  # eksctl is adding this and I have no idea why during delete...

deployment: _validate_environment _build_cluster _get_config _version _bootstrap _clean

# steps
_validate_environment:
	@(env | grep AWS_ACCESS_KEY_ID > /dev/null) || (echo "Error: AWS_ACCESS_KEY_ID is not set" && exit 1)
	@(env | grep AWS_SECRET_ACCESS_KEY > /dev/null) || (echo "Error: AWS_SECRET_ACCESS_KEY is not set" && exit 1)
	@(env | grep AWS_SESSION_TOKEN > /dev/null) || (echo "Error: AWS_SESSION_TOKEN is not set" && exit 1)
	@mkdir -p configs work

_version:
	@echo "Juno Version: $(JUNO_VERSION)"
	@echo "Primary Subnet: $(PRIMARY_SUBNET)"

_get_config:
	@eksctl utils write-kubeconfig --cluster $(ARGS) --kubeconfig $(KUBE)

_build_cluster:
	# build cluster
	@eksctl create cluster -f $(CONFIG) --kubeconfig $(KUBE) || echo "Cluster already exists, skipping creation."

_bootstrap:
	# install argo
	@$(KUBECTL) create namespace argocd || echo "Namespace argocd already exists, skipping creation."
	@$(KUBECTL) -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/refs/heads/master/manifests/install.yaml
	# pull juno bootstrap repository
	@rm -rf $(PWD)/work
	@git clone https://github.com/juno-fx/Juno-Bootstrap.git work/
	@cd work && git checkout $(JUNO_VERSION)
	# install juno
	$(JUNO)

_clean:
	@rm -rf $(PWD)/work

