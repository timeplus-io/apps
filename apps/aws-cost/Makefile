APP_NAME    ?= aws-cost
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

.PHONY: build install clean

build:
	rm -f $(OUT)
	zip -r $(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"

clean:
	rm -f $(OUT)
