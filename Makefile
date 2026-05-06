APP_DIR   ?= market-data
APP_NAME  ?= $(APP_DIR)
OUT       ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install

build:
	cd $(APP_DIR) && zip -r ../$(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"
