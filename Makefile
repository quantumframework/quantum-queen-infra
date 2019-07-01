VARS_FILE := variables.json
CLUSTER_NAME=$(shell cat $(VARS_FILE) | jq -r .cluster.name)
GKE_LOCATION=$(shell cat $(VARS_FILE) | jq -r .cluster.location.master)
VPC_NAME=$(shell cat $(VARS_FILE) | jq -r .cluster.network.name)


all: .terraform terraform.tfstate apply

apply:
	terraform apply --var-file $(VARS_FILE)

terraform.tfstate:
	@terraform import --var-file $(VARS_FILE)\
		google_compute_firewall.allow-cluster-endpoint-egress\
	 	$(VPC_NAME)-$(CLUSTER_NAME)-allow-cluster-master
	@terraform import --var-file $(VARS_FILE)\
		google_container_cluster.cluster\
		$(GKE_LOCATION)/$(CLUSTER_NAME)


.terraform:
	@terraform init
