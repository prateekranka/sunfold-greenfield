PROJECT      := SunfoldGreenfield.xcodeproj
SCHEME       := SunfoldGreenfield
CONFIG       := Debug
DESTINATION  ?= platform=iOS Simulator,name=Sunfold Cycle 1 iPad Air 13
BUILD_DIR    := build

.PHONY: help generate build test run clean

help:
	@echo "generate  Regenerate the Xcode project from project.yml"
	@echo "build     Build the app for the iPad simulator"
	@echo "test      Run the deterministic rule tests"
	@echo "clean     Remove generated project and build products"
	@echo ""
	@echo "Override the simulator with:  make build DESTINATION='platform=iOS Simulator,name=<name>'"

# project.yml is the source of truth. Run this after adding or removing any source
# file, or the new file will not be compiled.
generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(BUILD_DIR)

test: generate
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)
