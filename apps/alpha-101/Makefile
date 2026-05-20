APP_NAME    ?= alpha-101
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

TP_HOST     ?= localhost
TP_USER     ?= proton
TP_PASS     ?= proton@t+

.PHONY: build install backtest

build:
	zip -r $(OUT) manifest.yaml ddl/ dashboards/

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"

backtest:
	@cat backtest.sql | \
	  curl -s -u $(TP_USER):$(TP_PASS) --data-binary @- \
	    "http://$(TP_HOST):8123/?default_format=PrettyCompact"
