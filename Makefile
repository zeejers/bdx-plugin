.PHONY: patch minor major release help

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

patch minor major:
	@./scripts/release.sh $@

release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=x.y.z" >&2; exit 2)
	@./scripts/release.sh set $(VERSION)
