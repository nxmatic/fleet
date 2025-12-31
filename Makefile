FLOX_DIR ?= flox
RKE2_DIR ?= rke2
YQ ?= yq
FLOX_REMOTE ?= origin
RKE2_REMOTE ?= origin
FLOX_BRANCH ?= flox-subtree
RKE2_BRANCH ?= rke2-subtree

SUBTREE_REMOTE_default ?= origin

SUBTREE_DIR_flox ?= $(FLOX_DIR)
SUBTREE_BRANCH_flox ?= $(FLOX_BRANCH)
SUBTREE_REMOTE_flox ?= $(FLOX_REMOTE)
SUBTREE_REFRESH_LOCKS_flox ?= true

SUBTREE_DIR_rke2 ?= $(RKE2_DIR)
SUBTREE_BRANCH_rke2 ?= $(RKE2_BRANCH)
SUBTREE_REMOTE_rke2 ?= $(RKE2_REMOTE)
SUBTREE_REFRESH_LOCKS_rke2 ?= false

SUBTREE_NAME := $(strip $(name))
SUBTREE_DIR := $(SUBTREE_DIR_$(SUBTREE_NAME))
SUBTREE_BRANCH := $(SUBTREE_BRANCH_$(SUBTREE_NAME))
SUBTREE_REMOTE := $(or $(SUBTREE_REMOTE_$(SUBTREE_NAME)),$(SUBTREE_REMOTE_default))
SUBTREE_REFRESH_LOCKS := $(SUBTREE_REFRESH_LOCKS_$(SUBTREE_NAME))

SHELL := bash
.SHELLFLAGS := -euxo pipefail -c
.ONESHELL:

.PHONY: subtree-update check-subtree-clean finalize-merge flox-refresh-locks subtree-update-sync \
	ensure-subtree-context flox-update rke2-update flox-update-sync check-flox-clean

flox-update:
	$(MAKE) subtree-update name=flox

rke2-update:
	$(MAKE) subtree-update name=rke2

subtree-update: ensure-subtree-context finalize-merge check-subtree-clean subtree-update-sync
	@if [ "$(SUBTREE_REFRESH_LOCKS)" = "true" ]; then
		$(MAKE) flox-refresh-locks name=$(SUBTREE_NAME)
	fi
	: "[subtree-update] $(SUBTREE_NAME) applied"

flox-update-sync:
	$(MAKE) subtree-update-sync name=flox

subtree-update-sync: ensure-subtree-context
	git fetch --prune "$(SUBTREE_REMOTE)" "$(SUBTREE_BRANCH)"
	git subtree pull --prefix="$(SUBTREE_DIR)" "$(SUBTREE_REMOTE)" "$(SUBTREE_BRANCH)" --squash

check-flox-clean:
	$(MAKE) check-subtree-clean name=flox

check-subtree-clean: ensure-subtree-context
	if ! git diff --quiet -- "$(SUBTREE_DIR)"; then
		echo "Uncommitted changes detected inside $(SUBTREE_DIR). Please commit or stash them before updating." >&2;
		exit 1;
	fi
	untracked="$$(git ls-files --others --exclude-standard -- "$(SUBTREE_DIR)")";
	if [[ -n "$$untracked" ]]; then
		echo "Untracked files detected inside $(SUBTREE_DIR). Please add or clean them before updating." >&2;
		exit 1;
	fi

ensure-subtree-context:
	if [ -z "$(SUBTREE_NAME)" ]; then
		echo "Set name=flox or name=rke2 when invoking this target (e.g. 'make subtree-update name=flox')." >&2
		exit 1
	fi
	if [ -z "$(SUBTREE_DIR)" ] || [ -z "$(SUBTREE_BRANCH)" ]; then
		echo "Unsupported subtree '$(SUBTREE_NAME)' (expected flox or rke2)." >&2
		exit 1
	fi

# Auto-commit any completed merge so batch runs do not stop for editor prompts.
finalize-merge:
	if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			echo "Merge in progress with unresolved conflicts; resolve them before rerunning update-flox." >&2;
			exit 1;
		fi;
		: "Completing pending merge with default message...";
		GIT_MERGE_AUTOEDIT=no git commit --no-edit --quiet;
	fi

flox-refresh-locks:
	: "Refreshing flox manifest.lock files under $(FLOX_DIR) respecting include dependencies..."
	ROOT="$$(pwd -P)"
	FLOX_PATH="$$ROOT/$(FLOX_DIR)"
	shopt -s nullglob
	declare -A refreshed
	refresh_env() { \
		local env_dir="$$1"
		if [ -z "$$env_dir" ] || [ ! -d "$$env_dir/.flox" ]; then
			return 0
		fi
		if [[ -n "${refreshed[$$env_dir]+set}" ]]; then
			return 0
		fi
		local env_name="$$(basename "$$env_dir")"
		local descriptor="$$env_dir/$$env_name.yaml"
		local manifest="$$env_dir/.flox/env/manifest.toml"
		if [ -f "$$descriptor" ] && command -v $(YQ) >/dev/null 2>&1; then
			while IFS= read -r include_dir; do
				[ -z "$$include_dir" ] && continue
				case "$$include_dir" in
					"$$FLOX_PATH"/*) refresh_env "$$include_dir" ;
				esac
			done < <($(YQ) eval '(.includes // [])[]' "$$descriptor" 2>/dev/null || true)
		elif [ -f "$$manifest" ]; then
			while IFS= read -r include_dir; do
				[ -z "$$include_dir" ] && continue
				case "$$include_dir" in
					"$$FLOX_PATH"/*) refresh_env "$$include_dir" ;
				esac
			done < <(sed -n "s|^[[:space:]]*dir = '\(.*\)'|\1|p" "$$manifest")
		fi
		: "  - updating $$env_dir"
		flox upgrade --dir "$$env_dir" >/dev/null
		refreshed["$$env_dir"]=1
	}
	for env_dir in "$$FLOX_PATH"/*; do
		refresh_env "$$env_dir"
	done
