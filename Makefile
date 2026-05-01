.PHONY: patch minor major release help test-install test-install-shell

# Pick docker or fall back to podman so the test targets work for either runtime.
DOCKER ?= $(shell command -v docker 2>/dev/null || command -v podman 2>/dev/null)
TEST_IMAGE ?= ubuntu:24.04

help:
	@echo "Release workflow:"
	@echo "  make patch                  # bump x.y.Z+1"
	@echo "  make minor                  # bump x.Y+1.0"
	@echo "  make major                  # bump X+1.0.0"
	@echo "  make release VERSION=1.2.3  # set exact version"
	@echo ""
	@echo "Each target: bumps all .claude-plugin/plugin.json versions, runs"
	@echo "  git add . && lazy-changelog --prepend CHANGELOG.md"
	@echo "Then review + commit + tag + push manually."
	@echo ""
	@echo "Installer testing (clean-slate container):"
	@echo "  make test-install           # run scripts/install.sh in a fresh $(TEST_IMAGE)"
	@echo "  make test-install-shell     # same, then drop into a shell for inspection"
	@echo "  make test-install TEST_IMAGE=debian:12-slim   # override base image"

patch minor major:
	@./dev/release.sh $@

release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=x.y.z" >&2; exit 2)
	@./dev/release.sh set $(VERSION)

# Run the installer end-to-end inside a throwaway Linux container. Skips
# dolt because its installer wants sudo and dolt isn't load-bearing for
# validating the bdx flow itself. Mounts the working tree read-only and
# copies it into /tmp so the installer can run from any path without
# accidentally mutating the host repo.
_INSTALL_BOOTSTRAP = set -e; \
	export DEBIAN_FRONTEND=noninteractive; \
	apt-get update -qq && \
	apt-get install -y -qq --no-install-recommends curl jq git ca-certificates sudo >/dev/null; \
	cp -r /src /tmp/bdx-plugin; \
	cd /tmp/bdx-plugin; \
	bash scripts/install.sh --yes --skip-dolt

test-install:
	@test -n "$(DOCKER)" || (echo "no docker/podman on PATH — install one or set DOCKER=" >&2; exit 2)
	@$(DOCKER) run --rm -t \
		-v "$(CURDIR):/src:ro" \
		$(TEST_IMAGE) \
		bash -c '$(_INSTALL_BOOTSTRAP)'

test-install-shell:
	@test -n "$(DOCKER)" || (echo "no docker/podman on PATH — install one or set DOCKER=" >&2; exit 2)
	@$(DOCKER) run --rm -it \
		-v "$(CURDIR):/src:ro" \
		$(TEST_IMAGE) \
		bash -c '$(_INSTALL_BOOTSTRAP); echo; echo "--- installer finished. dropping into shell."; exec bash'
