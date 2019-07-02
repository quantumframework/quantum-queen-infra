#!/usr/bin/env make -f
VARS_FILE := variables.json
CLUSTER_NAME=$(shell cat $(VARS_FILE) | jq -r .cluster.name)
GKE_LOCATION=$(shell cat $(VARS_FILE) | jq -r .cluster.location.master)
POOL_NAME=$(shell cat $(VARS_FILE) | jq -r .cluster.pool.name)
PROJECT=$(shell cat $(VARS_FILE) | jq -r .platform.project)
SERVICE_ACCOUNT=$(shell cat $(VARS_FILE) | jq -r .cluster.service_account)
SERVICE_ACCOUNT := $(SERVICE_ACCOUNT)@$(PROJECT).iam.gserviceaccount.com
VPC_NAME=$(shell cat $(VARS_FILE) | jq -r .cluster.network.name)


init: .terraform terraform.tfstate

all: .terraform terraform.tfstate apply

plan: terraform.plan

apply:
	terraform apply --var-file $(VARS_FILE)

terraform.plan:
	terraform plan --var-file $(VARS_FILE)\
		-out terraform.plan


terraform.tfstate:
	@terraform import --var-file $(VARS_FILE)\
		google_compute_firewall.allow-cluster-endpoint-egress\
	 	$(VPC_NAME)-$(CLUSTER_NAME)-allow-cluster-master
	@terraform import --var-file $(VARS_FILE)\
		google_container_cluster.cluster\
		$(GKE_LOCATION)/$(CLUSTER_NAME)
	@terraform import --var-file $(VARS_FILE)\
		google_service_account.serviceaccount\
		$(SERVICE_ACCOUNT)
	@terraform import --var-file $(VARS_FILE)\
		google_project_iam_member.iam-logging-logwriter\
		"$(PROJECT) roles/logging.logWriter serviceAccount:$(SERVICE_ACCOUNT)"
	@terraform import --var-file $(VARS_FILE)\
		google_project_iam_member.iam-monitoring-metricwriter\
		"$(PROJECT) roles/monitoring.metricWriter serviceAccount:$(SERVICE_ACCOUNT)"
	@terraform import --var-file $(VARS_FILE)\
		google_project_iam_member.iam-monitoring-viewer\
		"$(PROJECT) roles/monitoring.viewer serviceAccount:$(SERVICE_ACCOUNT)"
	@terraform import --var-file $(VARS_FILE)\
		google_storage_bucket_iam_member.iam-gcr\
		"eu.artifacts.$(PROJECT).appspot.com roles/storage.objectViewer serviceAccount:$(SERVICE_ACCOUNT)"
	@terraform import --var-file $(VARS_FILE)\
		google_container_node_pool.pool $(GKE_LOCATION)/$(CLUSTER_NAME)/$(POOL_NAME)


.terraform:
	@terraform init


clean:
	@rm -rf .terraform
	@rm -rf terraform.tfstate
	@rm -rf terraform.plan
