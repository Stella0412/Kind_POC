SHELL := /bin/bash
ROOT := $(CURDIR)

.PHONY: build deploy smoke verify ci reproduce

build:
	bash work/scripts/build-images.sh

deploy:
	bash work/scripts/deploy.sh

smoke:
	bash work/scripts/smoke-test.sh

verify:
	bash work/scripts/verify.sh

ci: build deploy smoke verify

reproduce:
	bash work/scripts/reproduce.sh
