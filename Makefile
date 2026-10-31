SHELL := /bin/bash
.DEFAULT_GOAL := help

TF ?= terraform
TF_DIRS := terraform/traffic-shift

.PHONY: help schemas render manifests talos terraform tco lint shell bootstrap check clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

schemas: ## Build JSON schemas from the pinned CRDs (hack/crds.txt)
	./hack/schemas.sh

render: ## helm template every platform component with its values
	./hack/render.sh

manifests: schemas render ## Validate all manifests, overlays and rendered charts
	./hack/validate.sh

talos: ## Generate and validate the Talos machine configs
	./hack/talos.sh

terraform: ## fmt-check + validate the Terraform
	$(TF) fmt -check -recursive
	@set -e; for d in $(TF_DIRS); do \
		echo "==> $$d"; \
		$(TF) -chdir=$$d init -backend=false -input=false >/dev/null; \
		$(TF) -chdir=$$d validate; \
	done

tco: ## Run the TCO model tests and print the example
	cd tools/tco && python3 -m unittest -q && python3 tco.py example.toml

lint: ## yamllint
	yamllint -s .

shell: ## shellcheck the scripts
	shellcheck hack/*.sh migration/postgres/cutover.sh

bootstrap: ## Install Cilium and Argo CD on a fresh Talos cluster (needs KUBECONFIG)
	./hack/bootstrap.sh

check: lint shell manifests talos terraform tco ## Everything CI runs

clean: ## Remove generated files
	rm -rf .schemas .rendered .talos
	find . -type d -name .terraform -prune -exec rm -rf {} +
	find . -name .terraform.lock.hcl -delete
