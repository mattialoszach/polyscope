.DEFAULT_GOAL := build

BUILD_DIR ?= build
APPLICATIONS_DIR ?= /Applications

.PHONY: build setup install update run test icon help
build setup install update run test icon help:
	@POLYSCOPE_BUILD_DIR="$(BUILD_DIR)" POLYSCOPE_APPLICATIONS_DIR="$(APPLICATIONS_DIR)" ./scripts/macos.sh $@
