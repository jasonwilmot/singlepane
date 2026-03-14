# Velocity File Manager — Build System
# Usage: make [target]

.PHONY: all build run test clean lint format docs help

SCHEME       := Velocity
CONFIG       := Debug
BUILD_DIR    := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
XCFLAGS      := -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED_DATA)
SWIFT        := swift
XCODEBUILD   := xcodebuild
SWIFTLINT    := swiftlint
SWIFTFORMAT  := swiftformat

# ── Primary Targets ─────────────────────────────────────────

all: lint build test  ## Build everything and run tests

build:  ## Build the project
	@echo "Building $(SCHEME) ($(CONFIG))..."
	$(XCODEBUILD) $(XCFLAGS) build | xcpretty
	@echo "Build complete."

run: build  ## Build and run the app
	@open $(DERIVED_DATA)/Build/Products/$(CONFIG)/Velocity.app

release:  ## Build release configuration
	$(XCODEBUILD) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR)/Release build | xcpretty

# ── Testing ─────────────────────────────────────────────────

test:  ## Run all tests
	@echo "Running tests..."
	$(XCODEBUILD) $(XCFLAGS) test \
		-testPlan VelocityTests \
		-resultBundlePath $(BUILD_DIR)/test-results.xcresult | xcpretty

test-unit:  ## Run unit tests only
	$(XCODEBUILD) $(XCFLAGS) test \
		-only-testing:VelocityTests/Unit | xcpretty

test-integration:  ## Run integration tests only
	$(XCODEBUILD) $(XCFLAGS) test \
		-only-testing:VelocityTests/Integration | xcpretty

test-perf:  ## Run performance tests
	$(XCODEBUILD) $(XCFLAGS) test \
		-only-testing:VelocityPerformanceTests | xcpretty

test-coverage:  ## Generate test coverage report
	$(XCODEBUILD) $(XCFLAGS) test -enableCodeCoverage YES | xcpretty
	xcrun llvm-cov export \
		$(DERIVED_DATA)/Build/Products/$(CONFIG)/VelocityTests.xctest/Contents/MacOS/VelocityTests \
		-instr-profile $(DERIVED_DATA)/Build/ProfileData/*/Coverage.profdata \
		-format lcov > $(BUILD_DIR)/coverage.lcov
	@echo "Coverage report: $(BUILD_DIR)/coverage.lcov"

# ── Code Quality ────────────────────────────────────────────

lint:  ## Run SwiftLint
	@echo "Linting..."
	$(SWIFTLINT) lint --strict --quiet

lint-fix:  ## Auto-fix lint issues
	$(SWIFTLINT) lint --fix

format:  ## Format code with SwiftFormat
	$(SWIFTFORMAT) Sources/ Tests/ \
		--swiftversion 6.0 \
		--indent 4 \
		--maxwidth 120

format-check:  ## Check formatting without changes
	$(SWIFTFORMAT) Sources/ Tests/ --lint \
		--swiftversion 6.0 \
		--indent 4 \
		--maxwidth 120

# ── Index & Search Dev Tools ────────────────────────────────

index-build:  ## Build the search index for ~/Documents
	@echo "Building search index..."
	$(SWIFT) run VelocityIndexer --path ~/Documents --db $(BUILD_DIR)/dev-index.db

index-stats:  ## Show index statistics
	$(SWIFT) run VelocityIndexer --stats --db $(BUILD_DIR)/dev-index.db

index-search:  ## Search the dev index (usage: make index-search Q="query")
	$(SWIFT) run VelocityIndexer --search "$(Q)" --db $(BUILD_DIR)/dev-index.db

# ── Documentation ───────────────────────────────────────────

docs:  ## Generate documentation
	$(XCODEBUILD) docbuild -scheme $(SCHEME) \
		-derivedDataPath $(BUILD_DIR)/docs | xcpretty
	@echo "Docs built at $(BUILD_DIR)/docs"

docs-preview:  ## Preview documentation in browser
	@open $(BUILD_DIR)/docs/Build/Products/$(CONFIG)/Velocity.doccarchive

# ── Maintenance ─────────────────────────────────────────────

clean:  ## Clean build artifacts
	@echo "Cleaning..."
	rm -rf $(BUILD_DIR)
	$(XCODEBUILD) $(XCFLAGS) clean 2>/dev/null || true
	@echo "Clean complete."

reset: clean  ## Full reset — clean + remove caches
	rm -rf ~/Library/Caches/Velocity
	rm -rf ~/Library/Application\ Support/Velocity/search_index.db
	@echo "Reset complete."

deps:  ## Resolve package dependencies
	$(XCODEBUILD) -resolvePackageDependencies -scheme $(SCHEME)

loc:  ## Count lines of code
	@echo "Lines of code:"
	@find Sources -name '*.swift' | xargs wc -l | tail -1
	@echo "Lines of tests:"
	@find Tests -name '*.swift' | xargs wc -l | tail -1

# ── Help ────────────────────────────────────────────────────

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
