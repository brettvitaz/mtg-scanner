SHELL := /bin/bash

.PHONY: bootstrap api-bootstrap api-run api-test tree

bootstrap: api-bootstrap

api-bootstrap:
	./scripts/bootstrap-api.sh

api-run:
	./scripts/run-api.sh

api-test:
	./scripts/test-api.sh

tree:
	@find . -maxdepth 3 -type f | sort
