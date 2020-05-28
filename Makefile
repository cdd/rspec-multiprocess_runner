VERSIONS= $(shell grep '  - ' .travis.yml | cut -d- -f2)

$(VERSIONS): ## Make an image using this ruby version
	docker build --build-arg VERSION=$@ -t mpr.$@ .

latest: $(word $(words $(VERSIONS)), $(VERSIONS)) ## Make an image using the latest ruby in VERSIONS

%.test: % ## Run tests for the ruby version
	docker run mpr.$<

test tests: $(VERSIONS) ## Run tests for every ruby version
	# build the images in parallel and then run the tests one at a time afterward
	$(MAKE) -j1 $(VERSIONS:%=%.test)

%.shell: % ## Run a shell in the ruby version
	docker run -it -v $(PWD):/tmp/src -w /tmp/src mpr.$< bash

clean: ## cleans up the images
	docker rmi -f $(VERSIONS:%=mpr.%)

release: latest ## release the gem from in here
	docker run -it -v $(PWD):/tmp/src -v ~/.ssh:/root/.ssh -v ~/.gitconfig:/root/.gitconfig -v ~/.gem:/root/.gem \
		-w /tmp/src	mpr.$(word $(words $(VERSIONS)), $(VERSIONS)) ./docker_release.sh

.PHONY: help

help: ## https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
	@echo $(VERSIONS) | awk '{ printf "\033[36m%-30s\033[0m %s\n", "VERSIONS", $$0 }'
	@echo
	@grep -E '^[a-zA-Z_%$$.()-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; { gsub("\\\\n", "\n\t", $$2); printf "\033[36m%-30s\033[0m %s\n", $$1, $$2 }'

.DEFAULT_GOAL := help
