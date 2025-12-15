SHELL := /bin/bash

# Parámetros 
SERVICE ?= order-service
IMAGE_REGISTRY ?=
IMAGE_NAME ?= $(SERVICE)

# Versión/recursos del cluster (puedes overridear con: make K8S_VERSION=v1.33.1 ...)
K8S_VERSION ?= v1.32.2
MINIKUBE_CPUS ?= 4
MINIKUBE_MEMORY ?= 8192

# Normalización del registry (sin booleanos que confundan a make) 
# 1) strip espacios, 2) quita barra final, 3) arma repo si hay registry,
# 4) sanea una barra inicial accidental (evita "/user-service:tag").
REG_RAW      := $(strip $(IMAGE_REGISTRY))
REG_NOSLASH  := $(patsubst %/,%,$(REG_RAW))
IMAGE_REPO_0 := $(if $(REG_NOSLASH),$(REG_NOSLASH)/$(IMAGE_NAME),$(IMAGE_NAME))
IMAGE_REPO   := $(patsubst /%,%,$(IMAGE_REPO_0))

TAG ?= $(shell (git rev-parse --short HEAD 2>/dev/null) || date +%Y%m%d%H%M%S)
IMAGE := $(IMAGE_REPO):$(TAG)
K8S_IMAGE := $(IMAGE_REPO):$(TAG)

K8S_NS ?= default
K8S_DIR := k8s/$(SERVICE)
ARTIFACTS := artifacts

DOCKER ?= docker
KUBECTL ?= kubectl
MINIKUBE ?= minikube

SCAN_FAIL_SEVERITY ?= high
COSIGN_VERIFY ?= 0
SBOM_FORMAT ?= spdx-json

.DEFAULT_GOAL := pipeline

.PHONY: env
env:
	@echo "SERVICE=$(SERVICE)"
	@echo "IMAGE=$(IMAGE)"
	@echo "K8S_IMAGE=$(K8S_IMAGE)"
	@echo "TAG=$(TAG)"
	@echo "K8S_VERSION=$(K8S_VERSION)"

# BUILD
.PHONY: build
build:
	@if [ -n "$(REG_NOSLASH)" ]; then \
	  echo "[i] build local (para push a registry)"; \
	  $(DOCKER) build -t $(K8S_IMAGE) -f docker/Dockerfile.python-template .; \
	  echo "[OK] build local -> $(K8S_IMAGE)"; \
	else \
	  echo "[i] usando daemon de minikube para que el cluster vea la imagen"; \
	  eval $$($(MINIKUBE) docker-env); set -e; \
	  $(DOCKER) build -t $(K8S_IMAGE) -f docker/Dockerfile.python-template .; \
	  echo "[OK] build in-minikube -> $(K8S_IMAGE)"; \
	fi

.PHONY: push
push:
	@if [ -n "$(REG_NOSLASH)" ]; then \
	  $(DOCKER) push $(IMAGE); \
	else \
	  echo ">> No hay registro (IMAGE_REGISTRY vacío); 'push' no aplica"; \
	  exit 0; \
	fi

# SUPPLY CHAIN (SBOM / SCA / Firma) 
.PHONY: sbom
sbom:
	@mkdir -p $(ARTIFACTS)
	@if which syft >/dev/null 2>&1; then \
	  syft packages $(IMAGE) -o $(SBOM_FORMAT) > "$(ARTIFACTS)/$(SERVICE)-sbom.json"; \
	else \
	  echo "[i] syft no encontrado; usando contenedor (docker-archive)"; \
	  rm -f "$(ARTIFACTS)/$(SERVICE).tar"; \
	  $(DOCKER) image save $(IMAGE) -o "$(ARTIFACTS)/$(SERVICE).tar"; \
	  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" $(DOCKER) run --rm -v "$$(pwd)/$(ARTIFACTS)":/in anchore/syft:latest \
	    "docker-archive:/in/$(SERVICE).tar" -o $(SBOM_FORMAT) > "$(ARTIFACTS)/$(SERVICE)-sbom.json"; \
	fi
	@test -s "$(ARTIFACTS)/$(SERVICE)-sbom.json" || { echo "SBOM vacío"; exit 1; }
	@echo "SBOM -> $(ARTIFACTS)/$(SERVICE)-sbom.json"

.PHONY: scan
scan:
	@mkdir -p $(ARTIFACTS)
	@if which grype >/dev/null 2>&1; then \
	  grype $(IMAGE) --add-cpes-if-none -o sarif --fail-on $(SCAN_FAIL_SEVERITY) > "$(ARTIFACTS)/$(SERVICE)-grype.sarif"; \
	else \
	  echo "[i] grype no encontrado; usando contenedor (docker-archive)"; \
	  if [ ! -f "$(ARTIFACTS)/$(SERVICE).tar" ]; then $(DOCKER) image save $(IMAGE) -o "$(ARTIFACTS)/$(SERVICE).tar"; fi; \
	  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" $(DOCKER) run --rm -v "$$(pwd)/$(ARTIFACTS)":/in anchore/grype:latest \
	    "docker-archive:/in/$(SERVICE).tar" --add-cpes-if-none -o sarif --fail-on $(SCAN_FAIL_SEVERITY) \
	    > "$(ARTIFACTS)/$(SERVICE)-grype.sarif"; \
	fi
	@echo "GRYPE -> $(ARTIFACTS)/$(SERVICE)-grype.sarif (gate: fail-on $(SCAN_FAIL_SEVERITY))"

.PHONY: sign
sign:
	@if which cosign >/dev/null 2>&1; then COSIGN_YES=true cosign sign $(IMAGE); else echo "[i] cosign no encontrado (skip)"; fi
ifeq ($(COSIGN_VERIFY),1)
	@if which cosign >/dev/null 2>&1; then cosign verify $(IMAGE) >/dev/null && echo "Verificación de firma OK"; fi
endif

# K8S 
.PHONY: k8s-prepare
k8s-prepare:
	@mkdir -p $(ARTIFACTS)
	@if [ "$(SERVICE)" = "order-service" ]; then \
	  sed -E 's|image:\s*[^[:space:]]+|image: $(K8S_IMAGE)|' $(K8S_DIR)/deployment-and-service.yaml > $(ARTIFACTS)/order-service.yaml; \
	  echo "Manifest -> $(ARTIFACTS)/order-service.yaml"; \
	else \
	  sed -E 's|image:\s*[^[:space:]]+|image: $(K8S_IMAGE)|' $(K8S_DIR)/deployment-and-service.yaml > $(ARTIFACTS)/user-service.yaml; \
	  echo "Manifest -> $(ARTIFACTS)/user-service.yaml"; \
	fi

.PHONY: minikube-up
minikube-up:
	@echo "[i] Asegurando minikube (k8s=$(K8S_VERSION))"
	$(MINIKUBE) status >/dev/null 2>&1 || \
	$(MINIKUBE) start --driver=docker --kubernetes-version=$(K8S_VERSION) --cpus=$(MINIKUBE_CPUS) --memory=$(MINIKUBE_MEMORY)

.PHONY: k8s-apply
k8s-apply:
	@if [ "$(SERVICE)" = "order-service" ]; then \
	  $(KUBECTL) apply -f $(ARTIFACTS)/order-service.yaml -n $(K8S_NS); \
	else \
	  $(KUBECTL) apply -f $(ARTIFACTS)/user-service.yaml -n $(K8S_NS); \
	fi
	$(KUBECTL) rollout status deploy/$(SERVICE) -n $(K8S_NS) --timeout=180s

.PHONY: smoke
smoke:
	@if [ "$(SERVICE)" = "order-service" ]; then ./scripts/minikube_smoke.sh order-service 8001 $(K8S_NS); \
	else ./scripts/minikube_smoke.sh user-service 8000 $(K8S_NS); fi

# Flujos de alto nivel 
.PHONY: dev
dev: env minikube-up build k8s-prepare k8s-apply smoke
	@echo "[DEV] OK -> $(SERVICE) @ $(K8S_IMAGE)"

.PHONY: ci
ci: env build push sbom sign scan k8s-prepare minikube-up k8s-apply smoke
	@echo "[CI] OK -> $(SERVICE) @ $(IMAGE) (via registry)"

.PHONY: pipeline
pipeline: dev

.PHONY: minikube-config
minikube-config:
	$(MINIKUBE) config set driver docker
	$(MINIKUBE) config set kubernetes-version $(K8S_VERSION)
	$(MINIKUBE) config set cpus $(MINIKUBE_CPUS)
	$(MINIKUBE) config set memory $(MINIKUBE_MEMORY)
