FLOX_DIR ?= flox
FLOX_REMOTE ?= origin
FLOX_BRANCH ?= flox-subtree

SHELL ?= bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:

.PHONY: update-flox check-flox-clean

update-flox: check-flox-clean
	git fetch --prune "$(FLOX_REMOTE)" "$(FLOX_BRANCH)"
	git subtree pull --prefix="$(FLOX_DIR)" "$(FLOX_REMOTE)" "$(FLOX_BRANCH)" --squash

check-flox-clean:
	@if ! git diff --quiet -- "$(FLOX_DIR)"; then \
		echo "Uncommitted changes detected inside $(FLOX_DIR). Please commit or stash them before updating." >&2; \
		exit 1; \
	fi
	@untracked="$$(git ls-files --others --exclude-standard -- "$(FLOX_DIR)")"; \
	if [[ -n "$$untracked" ]]; then \
		echo "Untracked files detected inside $(FLOX_DIR). Please add or clean them before updating." >&2; \
		exit 1; \
	fi
