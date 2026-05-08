APP         ?= market-data
NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default
BASE_URL    ?= http://localhost:9090
GITHUB_REPO        ?= timeplus-io/apps
GITHUB_RELEASE_TAG ?= registry-v1.0.0

APPS        := market-data github cep

.PHONY: build install build-all install-all registry-index registry-index-github registry-serve registry-docker $(APPS)

build:
	$(MAKE) -C apps/$(APP) build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

install:
	$(MAKE) -C apps/$(APP) install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

build-all:
	@for app in $(APPS); do $(MAKE) -C apps/$$app build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT); done

install-all:
	@for app in $(APPS); do $(MAKE) -C apps/$$app install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT); done

# Registry targets

registry-index: build-all
	pip3 install -q -r registry/requirements.txt
	BASE_URL=$(BASE_URL) python3 registry/build.py

registry-serve: registry-index
	@echo ""
	@echo "Registry running at $(BASE_URL)"
	@echo "Set in .neutron.yaml:  app-registry-url: $(BASE_URL)/index.json"
	@echo ""
	cd registry && python3 -m http.server 9090

registry-index-github:
	pip3 install -q -r registry/requirements.txt
	GITHUB_REPO=$(GITHUB_REPO) GITHUB_RELEASE_TAG=$(GITHUB_RELEASE_TAG) python3 registry/build.py

registry-docker:
	BASE_URL=$(BASE_URL) docker compose up --build
