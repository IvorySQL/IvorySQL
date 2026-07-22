PYTHON ?= python3
COMPOSE ?= docker compose
HARNESS := $(PYTHON) patroni_harness.py

.PHONY: build config preflight up status verify switchover failover logs down clean test

build:
	$(COMPOSE) build

config:
	$(COMPOSE) config --quiet

preflight:
	$(HARNESS) preflight

up:
	$(COMPOSE) up --detach --build etcd ivory-1 ivory-2 ivory-3 haproxy
	$(COMPOSE) exec ivory-1 python3 /usr/local/libexec/patroni_harness.py wait --timeout 5m

status:
	$(COMPOSE) exec ivory-1 python3 /usr/local/libexec/patroni_harness.py status

verify:
	$(COMPOSE) --profile verify run --no-deps --rm verifier

switchover:
	$(COMPOSE) exec ivory-1 python3 /usr/local/libexec/patroni_harness.py switchover --yes

failover:
	$(COMPOSE) exec ivory-1 python3 /usr/local/libexec/patroni_harness.py failover --yes

logs:
	$(COMPOSE) logs --follow --tail 100

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --volumes --remove-orphans

test:
	$(PYTHON) -m unittest discover -s tests -v
