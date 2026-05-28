APP         ?= market-data
NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default
GITHUB_REPO        ?= timeplus-io/apps
GITHUB_RELEASE_TAG ?= registry-v1.0.0

APPS        := market-data github cep game-feature-pipeline hacker-news invest-insights cisco-asa-ddos bluesky aws-cost taxi-fleet geo-ip-lookup

.PHONY: build install build-all install-all registry-serve registry-index-github registry-docker $(APPS)

build:
	$(MAKE) -C apps/$(APP) build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

install:
	$(MAKE) -C apps/$(APP) install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

build-all:
	@for app in $(APPS); do $(MAKE) -C apps/$$app build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT); done

install-all:
	@for app in $(APPS); do $(MAKE) -C apps/$$app install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT); done

# Registry targets

registry-serve: build-all
	@echo ""
	@echo "Registry running at http://localhost:9090"
	@echo "Set in .neutron.yaml:  app-registry-url: http://localhost:9090/index.json"
	@echo ""
	pip3 install -q -r registry/requirements.txt
	python3 registry/server.py

registry-index-github:
	pip3 install -q -r registry/requirements.txt
	GITHUB_REPO=$(GITHUB_REPO) GITHUB_RELEASE_TAG=$(GITHUB_RELEASE_TAG) python3 registry/build.py

registry-docker:
	docker compose up --build
