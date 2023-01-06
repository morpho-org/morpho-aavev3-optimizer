-include .env
.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

NETWORK ?= avalanche-mainnet


install:
	yarn
	foundryup
	forge install

contracts:
	FOUNDRY_TEST=/dev/null forge build --via-ir --sizes --force

test:
	forge test -vvv

test-%:
	@FOUNDRY_MATCH_TEST=$* make test

coverage:
	forge coverage --report lcov
	lcov --remove lcov.info -o lcov.info "test/*"

lcov-html:
	@echo Transforming the lcov coverage report into html
	genhtml lcov.info -o coverage

gas-report:
	forge test --gas-report


.PHONY: contracts test coverage
