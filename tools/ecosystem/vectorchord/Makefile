PYTHON ?= python3
COMPOSE ?= docker compose
HARNESS := $(PYTHON) vector_harness.py

.PHONY: build config preflight up setup smoke benchmark audit verify logs down clean test

build:
	$(COMPOSE) build

config:
	$(COMPOSE) config --quiet

preflight:
	$(HARNESS) preflight

up:
	$(COMPOSE) up --detach --build database

setup:
	$(COMPOSE) exec database $(HARNESS) setup

smoke:
	$(COMPOSE) exec database $(HARNESS) smoke

benchmark:
	$(COMPOSE) exec database $(HARNESS) benchmark

audit:
	$(COMPOSE) exec database $(HARNESS) audit

verify:
	$(COMPOSE) --profile verify run --rm verifier

logs:
	$(COMPOSE) logs --follow --tail 100

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --volumes --remove-orphans

test:
	$(PYTHON) -m unittest discover -s tests -v
