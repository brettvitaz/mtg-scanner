SHELL := /bin/bash

.PHONY: bootstrap api-bootstrap api-run api-test api-lint api-update-mtgjson api-import-ck-prices ios-lint lint tree

bootstrap: api-bootstrap

api-bootstrap:
	./scripts/bootstrap-api.sh

api-run:
	./scripts/run-api.sh

api-test:
	./scripts/test-api.sh

api-lint:
	./scripts/lint-api.sh

ios-lint:
	./scripts/lint-ios.sh

api-update-mtgjson:
	PYTHONPATH=services/api .venv/bin/python scripts/update_mtgjson.py

api-import-ck-prices:
	PYTHONPATH=services/api .venv/bin/python scripts/import_ck_prices.py

lint: api-lint ios-lint

tree:
	@find . -maxdepth 3 -type f | sort
