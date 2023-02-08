-include .env
.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

NETWORK ?= ethereum-mainnet


install:
	yarn
	foundryup
	forge install

contracts:
	FOUNDRY_TEST=/dev/null forge build --via-ir --extra-output-files irOptimized --sizes --force


test:
	forge test -vvv

test-unit:
	@FOUNDRY_MATCH_CONTRACT=TestUnit make test

test-internal:
	@FOUNDRY_MATCH_CONTRACT=TestInternal make test

test-integration:
	@FOUNDRY_MATCH_CONTRACT=TestIntegration make test


test-%:
	@FOUNDRY_MATCH_TEST=$* make test

test-unit-%:
	@FOUNDRY_MATCH_TEST=$* make test-unit

test-internal-%:
	@FOUNDRY_MATCH_TEST=$* make test-internal

test-integration-%:
	@FOUNDRY_MATCH_TEST=$* make test-integration


test/%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

test-unit/%:
	@FOUNDRY_MATCH_CONTRACT=TestUnit$* make test

test-internal/%:
	@FOUNDRY_MATCH_CONTRACT=TestInternal$* make test

test-integration/%:
	@FOUNDRY_MATCH_CONTRACT=TestIntegration$* make test


coverage:
	forge coverage --report lcov
	lcov --remove lcov.info -o lcov.info "test/*"

lcov-html:
	@echo Transforming the lcov coverage report into html
	genhtml lcov.info -o coverage

gas-report:
	forge test --match-contract TestIntegration --gas-report


.PHONY: contracts test coverage
