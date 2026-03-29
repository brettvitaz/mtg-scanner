SHELL := /bin/bash

.PHONY: bootstrap api-bootstrap api-run api-test api-lint ios-lint lint tree

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

lint: api-lint ios-lint

tree:
	@find . -maxdepth 3 -type f | sort
