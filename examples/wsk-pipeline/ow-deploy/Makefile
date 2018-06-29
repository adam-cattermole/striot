prefix = adamcattermole

base = ow-deploy-base/striot
deploy = ow-function
license = $(base)/LICENSE
cabal = $(base)/striot.cabal

src_dir := $(base)/src
in_srcs := $(wildcard ../../../src/*.hs) $(wildcard ../../../src/**/*.hs)
out_srcs := $(subst ..,$(base),$(in_srcs))


.PHONY: base
base: $(cabal) $(license) $(out_srcs)
	@echo "Building image $(prefix)/whisk-haskell-base"
	@docker build -t $(prefix)/whisk-haskell-base ow-deploy-base

$(out_srcs): $(src_dir) $(in_srcs)
	@cp -R ../../../src/* $(src_dir)

$(cabal): $(src_dir) ../../../striot.cabal
	@cp -R ../../../striot.cabal $(base)/

$(license): $(src_dir) ../../../LICENSE
	@cp -R ../../../LICENSE $(base)/

$(src_dir):
	@mkdir -p $(src_dir)


.PHONY: deploy
deploy: base
	@echo "Building image $(prefix)/whisk-test"
	@docker build -t $(prefix)/whisk-test $(deploy)


.PHONY: clean
clean:
	@echo "Removing striot-base/striot"
	@rm -rf $(base)
	# @if [ -n "$$(docker images -q $(prefix)/whisk-haskell-base)" ]; then \
	# 	docker rmi $(prefix)/whisk-haskell-base; \
	# fi
	# @if [ -n "$$(docker images -q $(prefix)/whisk-test)" ]; then \
	# 	docker rmi $(prefix)/whisk-test; \
	# fi
