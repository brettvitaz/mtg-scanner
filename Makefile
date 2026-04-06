SHELL := /bin/bash

.PHONY: bootstrap api-bootstrap api-run api-test api-lint api-security api-update-mtgjson api-import-ck-prices ios-build ios-test ios-lint lint security tree

bootstrap: api-bootstrap

api-bootstrap:
	./scripts/bootstrap-api.sh

api-run:
	./scripts/run-api.sh

api-test:
	./scripts/test-api.sh

api-lint:
	./scripts/lint-api.sh

ios-build:
	xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner \
	  -sdk iphonesimulator -configuration Debug build

ios-test:
	xcodebuild test \
	  -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner \
	  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
	  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO

ios-lint:
	./scripts/lint-ios.sh

api-update-mtgjson:
	PYTHONPATH=services/api .venv/bin/python scripts/update_mtgjson.py

api-import-ck-prices:
	PYTHONPATH=services/api .venv/bin/python scripts/import_ck_prices.py

api-security:
	./scripts/security-api.sh

lint: api-lint ios-lint

security: api-security

tree:
	@find . -maxdepth 3 -type f | sort
