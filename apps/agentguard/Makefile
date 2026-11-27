APP_NAME    ?= agentguard
OUT         ?= $(APP_NAME).tpapp

NEUTRON_URL ?= http://localhost:8000
TENANT      ?= default

CHECK         := python3 ../../scripts/check_tpapp.py
THREE_VERSION ?= 0.184.0
THREE_DIR     := web/agent-rooms/vendor

.PHONY: build install test test-codex-hooks vendor vendor-context

# The custom UI directories come from the manifest (`uis[].dir`). The package is built
# under a temporary name and only becomes $(OUT) once it passes the check, so a bad
# package is never left where `make install` would pick it up. -FS drops entries whose
# files are gone, so a leftover temporary file cannot carry stale content.
build:
	zip -r -X -FS $(OUT).tmp manifest.yaml ddl/ dashboards/ $$($(CHECK) --ui-dirs manifest.yaml) -x '*.DS_Store'
	$(CHECK) $(OUT).tmp
	mv $(OUT).tmp $(OUT)

install: build
	curl -X POST $(NEUTRON_URL)/$(TENANT)/api/v1beta2/apps/install -F "file=@$(OUT)"

# Unit tests for the custom UI's logic (Node 20+). They live outside web/, so they are not packaged.
test:
	node --test

# Live check of the Codex hook-event path: replays a recorded session into a Timeplus that has this
# app installed (TIMEPLUS_URL, default http://localhost:8123; TIMEPLUS_USER; TIMEPLUS_PASSWORD).
test-codex-hooks:
	node tests/codex-hooks/replay.mjs

# Refresh the three.js copy shipped inside the Agent Rooms bundle.
vendor:
	curl -fsSL https://unpkg.com/three@$(THREE_VERSION)/build/three.module.min.js -o $(THREE_DIR)/three.module.min.js
	curl -fsSL https://unpkg.com/three@$(THREE_VERSION)/build/three.core.min.js -o $(THREE_DIR)/three.core.min.js

# Refresh the console-context helper shipped inside the Agent Rooms bundle (a test fails when it drifts).
vendor-context:
	cp ../../skill/assets/tp-context.js $(THREE_DIR)/tp-context.js
