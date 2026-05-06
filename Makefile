APP         ?= market-data
NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install

build:
	$(MAKE) -C apps/$(APP) build NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)

install:
	$(MAKE) -C apps/$(APP) install NEUTRON_URL=$(NEUTRON_URL) TENANT=$(TENANT)
