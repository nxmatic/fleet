FLOX_DIR ?= flox
FLOX_REMOTE ?= origin
FLOX_BRANCH ?= flox-subtree

SHELL ?= bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:

.PHONY: update-flox check-flox-clean finalize-merge

flox-update: finalize-merge check-flox-clean
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

# Auto-commit any completed merge so batch runs do not stop for editor prompts.
finalize-merge:
	@if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then \
		if git diff --name-only --diff-filter=U | grep -q .; then \
			echo "Merge in progress with unresolved conflicts; resolve them before rerunning update-flox." >&2; \
			exit 1; \
		fi; \
		echo "Completing pending merge with default message..."; \
		GIT_MERGE_AUTOEDIT=no git commit --no-edit --quiet; \
	fi
