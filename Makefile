SHELL := /bin/bash
XCODE_BUILD_SERVER ?= $(shell command -v xcode-build-server 2>/dev/null)
IOS_SOURCEKIT_PACKAGE_DIR := apps/ios/MTGScannerKit
IOS_SOURCEKIT_RESULT_BUNDLE := tmp/ios-build-result.xcresult
IOS_TEST_SIMULATOR_ID ?= $(shell xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && $$2 ~ /^[0-9A-F-]+$$/ { print $$2; exit }')
IOS_TEST_SCHEME ?= MTGScannerKitTests
IOS_TEST_DESTINATION ?= id=$(IOS_TEST_SIMULATOR_ID)
IOS_TEST_CURRENT_DEVICE ?= iPhone 17
IOS_TEST_CURRENT_DESTINATION ?= platform=iOS Simulator,OS=26.4,name=$(IOS_TEST_CURRENT_DEVICE)
IOS_TEST_TABLET_DEVICE ?= iPad Air 11-inch (M4)
IOS_TEST_TABLET_DESTINATION ?= platform=iOS Simulator,OS=26.4,name=$(IOS_TEST_TABLET_DEVICE)

.PHONY: bootstrap api-bootstrap api-setup api-clean api-run api-tmux api-test api-lint api-security api-update-mtgjson api-import-ck-prices api-update-pricing api-eval ios-build ios-test ios-test-current ios-test-tablet ios-test-matrix ios-lint ios-snapshot ios-snapshot-all lint security tree

bootstrap: api-bootstrap

api-bootstrap:
	./scripts/bootstrap-api.sh

api-run:
	./scripts/run-api.sh

api-tmux:
	./scripts/tmux-api-run.sh

api-setup: api-bootstrap api-import-ck-prices api-update-mtgjson api-update-pricing

api-clean:
	rm -f services/api/data/ck_prices/ck_prices.sqlite
	rm -f services/api/data/mtgjson/mtgjson.sqlite
	rm -f services/api/data/pricing/model_prices.json
	rm -f services/api/data/mtgjson/manifest.json

api-test:
	./scripts/test-api.sh

api-lint:
	./scripts/lint-api.sh

api-eval:
	./scripts/run-evals.sh $(EVAL_ARGS)

ios-build:
	@if [ -n "$(XCODE_BUILD_SERVER)" ]; then \
	  (cd $(IOS_SOURCEKIT_PACKAGE_DIR) && "$(XCODE_BUILD_SERVER)" config -workspace ../MTGScanner.xcworkspace -scheme MTGScanner); \
	fi
	rm -rf $(IOS_SOURCEKIT_RESULT_BUNDLE)
	xcodebuild -workspace apps/ios/MTGScanner.xcworkspace -scheme MTGScanner \
	  -sdk iphonesimulator -configuration Debug \
	  -resultBundlePath $(IOS_SOURCEKIT_RESULT_BUNDLE) build

ios-test:
	xcodebuild test \
	  -workspace apps/ios/MTGScanner.xcworkspace -scheme $(IOS_TEST_SCHEME) \
	  -destination '$(IOS_TEST_DESTINATION)' \
	  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO

ios-test-current:
	xcodebuild test \
	  -workspace apps/ios/MTGScanner.xcworkspace -scheme $(IOS_TEST_SCHEME) \
	  -destination '$(IOS_TEST_CURRENT_DESTINATION)' \
	  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO

ios-test-tablet:
	xcodebuild test \
	  -workspace apps/ios/MTGScanner.xcworkspace -scheme $(IOS_TEST_SCHEME) \
	  -destination '$(IOS_TEST_TABLET_DESTINATION)' \
	  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO

ios-test-matrix: ios-test ios-test-current ios-test-tablet

ios-lint:
	./scripts/lint-ios.sh

IOS_SNAPSHOT_ROUTES ?= settings scan

ios-snapshot: ios-build
	ROUTE=$${ROUTE:-settings} ./scripts/ios-screenshot.sh "$${ROUTE:-settings}"

ios-snapshot-all: ios-build
	set -e; for route in $(IOS_SNAPSHOT_ROUTES); do ROUTE=$$route ./scripts/ios-screenshot.sh "$$route"; done

api-update-mtgjson:
	PYTHONPATH=services/api .venv/bin/python scripts/update_mtgjson.py

api-import-ck-prices:
	PYTHONPATH=services/api .venv/bin/python scripts/import_ck_prices.py

api-update-pricing:
	PYTHONPATH=services/api .venv/bin/python scripts/update_llm_pricing.py

api-security:
	./scripts/security-api.sh

lint: api-lint ios-lint

security: api-security

tree:
	@find . -maxdepth 3 -type f | sort
