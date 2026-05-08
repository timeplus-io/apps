APP         ?= market-data
NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

APPS        := market-data github cep

.PHONY: build install build-all install-all $(APPS)

build:
	$(MAKE) -C apps/$(APP) build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

install:
	$(MAKE) -C apps/$(APP) install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

build-all:
	@for app in $(APPS); do $(MAKE) -C apps/$$app build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT); done

install-all:
	@for app in $(APPS); do $(MAKE) -C apps/$$app install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT); done
