APP         ?= market-data
NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default
BASE_URL    ?= http://localhost:9090

APPS        := market-data github cep

.PHONY: build install build-all install-all registry-index registry-serve registry-docker $(APPS)

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

registry-docker:
	BASE_URL=$(BASE_URL) docker compose up --build
