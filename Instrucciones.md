### Laboratorio: DevSecOps total: Docker -> Cadena de suministro -> CI -> Kubernetes (local primero, reproducible)

Este laboratorio, cubre el desarrollo local con Docker/Compose, **supply chain** (SBOM, SCA y firma), **CI local con registro**, y despliegue en **Kubernetes (Minikube)**, con verificación de salud y recolección de evidencias.

### 0. Estructura relevante del paquete

* **Raíz**
  `Makefile`, `Instrucciones.md`, `requirements.txt`, `server.py`, `healthcheck.py`
* **Docker**
  `docker/Dockerfile.python-template`  <- sin `apt`, healthcheck en Python
* **Tests (Compose)**
  `docker-compose.user.test.yml`, `docker-compose.order.test.yml`
* **Kubernetes**
  `k8s/user-service/deployment-and-service.yaml`
  `k8s/order-service/deployment-and-service.yaml`
  *(con probes a `/health` e `imagePullPolicy: IfNotPresent`)*
* **Scripts**
  `scripts/env.sh`, `pipeline.sh`, `run_all.sh`, `minikube_smoke.sh`,
  `muestra_salidas.sh`, `pre-push.ejemplo.sh`, `tag.sh`, `wait-for-http.sh`
* **Artefactos**
  `artifacts/user-service-sbom.json`, `user-service-grype.sarif`,
  `user-service.tar`, `user-service.yaml`, `order-service.yaml`
* **Supply chain**
  `supply-chain/Instrucciones.md`

### 1. Prerrequisitos

* **Docker** y **Docker Compose v2**
* **Python 3.10+** (para `healthcheck.py`)
* **kubectl** y **Minikube**
* *(Opcional, para regenerar artefactos)*: **syft**, **grype**, **cosign**

> **Windows/WSL2**: usa **Docker Desktop** con integración WSL2 activada.


### 2. Preparación de entorno

```bash
cd Laboratorio11
python -m venv .venv && source .venv/bin/activate     # opcional (cambia de nombre)
pip install -r requirements.txt                       # opcional

# Variables comunes del laboratorio
source scripts/env.sh

# (si tu Makefile expone el target 'env')
make env SERVICE=user-service
# Ejemplo de salida: SERVICE=user-service TAG=20251108... IMAGE=user-service:20251108...
```

> `scripts/env.sh` centraliza nombres y tags. Ajusta ahí lo necesario.

### 3. Desarrollo local (DEV) - pruebas con Docker Compose

**Objetivo:** compilar, levantar contenedor de prueba y comprobar `/health` con un contenedor `sut`.

#### 3.1 User Service

**Con Makefile**

```bash
make dev SERVICE=user-service
```

**Con Docker Compose (fallback)**

```bash
docker compose -f docker-compose.user.test.yml up --build --abort-on-container-exit --exit-code-from sut
docker compose -f docker-compose.user.test.yml down -v
```

**Qué observar**

* Logs de build OK
* Mensaje final tipo **`SUT OK`** (porque el `sut` hace `curl http://app:8000/health` -> **200**)
* Código de salida **0**

#### 3.2 Order Service

**Con Makefile**

```bash
make dev SERVICE=order-service
```

**Con Docker Compose (fallback)**

```bash
docker compose -f docker-compose.order.test.yml up --build --abort-on-container-exit --exit-code-from sut
docker compose -f docker-compose.order.test.yml down -v
```

**Qué observar**

* Build OK
* **`SUT OK`** para `http://app:8001/health`

> **Si falla**: confirma que el servicio expone `/health` y el **puerto** correcto.


### 4. Supply Chain (SEC) - SBOM + SCA (SARIF + gate) + Firma

**Objetivo:** generar SBOM, ejecutar análisis de vulnerabilidades con **gate** y **firmar/verificar** la imagen.
Usaremos `user-service` como ejemplo (puedes replicar con `order-service`).

#### 4.1 Generar SBOM

**Con Makefile**

```bash
make sbom SERVICE=user-service
```

**Manual con Syft (si ya tienes un .tar)**

```bash
syft packages docker-archive:artifacts/user-service.tar -o json > artifacts/user-service-sbom.json
```

**Salida esperada:** `artifacts/user-service-sbom.json` (inventario de componentes).

#### 4.2 SCA con gate (Grype -> SARIF)

**Con Makefile (gate estricto)**

```bash
SCAN_FAIL_SEVERITY=high make scan SERVICE=user-service
```

**Manual con Grype**

```bash
grype docker-archive:artifacts/user-service.tar -o sarif > artifacts/user-service-grype.sarif
```

* Artefacto: `artifacts/user-service-grype.sarif`
* Si detecta **High/Critical**, el **target falla** (gate).
* **Solo para demo** (relajar umbral):

  ```bash
  SCAN_FAIL_SEVERITY=critical make scan SERVICE=user-service
  ```

#### 4.3 Firma y verificación (Cosign)

```bash
make sign SERVICE=user-service              # firma
COSIGN_VERIFY=1 make sign SERVICE=user-service  # firma + verify
```

#### 4.4 Evidencias de supply chain

```bash
mkdir -p .evidence/sbom .evidence/scan .evidence/logs
cp artifacts/*sbom*.json .evidence/sbom/ 2>/dev/null || true
cp artifacts/*grype*.sarif .evidence/scan/ 2>/dev/null || true
bash scripts/muestra_salidas.sh
```

> Conceptos ampliados en `supply-chain/Instrucciones.md`.

### 5. CI local con registro (push + firma)

**Objetivo:** ejecutar pipeline "tipo CI" completa con push a un **registro** (por ejemplo GHCR).

1. Configura registro y autentícate

```bash
export IMAGE_REGISTRY=ghcr.io/TU_ORG
docker login ghcr.io
```

2. Ejecuta pipeline

```bash
make ci SERVICE=order-service
# o
make pipeline SERVICE=order-service
```

**Qué observar**

* **build -> test -> sbom -> scan (gate) -> push -> sign/verify**
* Imagen publicada como `ghcr.io/TU_ORG/order-service:<TAG>`

**Evidencia**

```bash
make ci SERVICE=order-service | tee .evidence/logs/ci-order-$(date +%F-%H%M).txt
```

### 6. Despliegue en Kubernetes (OPS) - Minikube

**Objetivo:** desplegar **cada servicio** y validar `/health` desde el cluster.

> Los manifests vienen con `imagePullPolicy: IfNotPresent`. Elige **una** de estas estrategias:

#### Estrategia A - Construir dentro del daemon de Minikube (sin registro)

1. Apunta Docker al daemon de Minikube

```bash
minikube start --driver=docker
eval $(minikube docker-env)                      # Linux/macOS
# PowerShell: minikube -p minikube docker-env | Invoke-Expression
```

2. Construye las imágenes y aplica manifests

```bash
make build SERVICE=user-service
make build SERVICE=order-service

kubectl apply -f k8s/user-service/deployment-and-service.yaml
kubectl apply -f k8s/order-service/deployment-and-service.yaml
kubectl get deploy,svc,pod -o wide
```

#### Estrategia B - Usar un registro (pull)

1. Publica imágenes (ver sección CI)
2. Asegúrate de que los manifests señalen `image: ghcr.io/TU_ORG/SERVICE-NAME:<TAG>`
3. Aplica

```bash
kubectl apply -f k8s/user-service/deployment-and-service.yaml
kubectl apply -f k8s/order-service/deployment-and-service.yaml
```
#### Verificación de readiness y health

**Smoke test por port-forward automático**

```bash
./scripts/minikube_smoke.sh user-service 8000
./scripts/minikube_smoke.sh order-service 8001
```

**URL del servicio y healthcheck**

```bash
USER_URL=$(minikube service user-service --url)
ORDER_URL=$(minikube service order-service --url)

bash scripts/wait-for-http.sh "$USER_URL/health" 60
bash scripts/wait-for-http.sh "$ORDER_URL/health" 60

python healthcheck.py --url "$USER_URL/health" --timeout 30
python healthcheck.py --url "$ORDER_URL/health" --timeout 30
```

**Evidencia rápida**

```bash
kubectl get deploy,svc,pods -o wide | tee .evidence/logs/k8s-overview-$(date +%F-%H%M).txt
bash scripts/muestra_salidas.sh
```

#### Limpieza

```bash
kubectl delete -f k8s/user-service/deployment-and-service.yaml || true
kubectl delete -f k8s/order-service/deployment-and-service.yaml || true
# Opcional: minikube delete
```

### 7. Resumen con todo lo esencial

```bash
# 0) prep
cd Laboratorio11
source scripts/env.sh
make env SERVICE=user-service

# 1) dev local (ambos servicios)
make dev SERVICE=user-service
make dev SERVICE=order-service

# 2) supply chain (mínimo requerido)
make sbom SERVICE=user-service
SCAN_FAIL_SEVERITY=high make scan SERVICE=user-service
make sign SERVICE=user-service

# 3) k8s (elige UNA estrategia)
# 3.a build dentro de minikube
minikube start --driver=docker
eval $(minikube docker-env)
make build SERVICE=user-service
make build SERVICE=order-service
kubectl apply -f k8s/user-service/deployment-and-service.yaml
kubectl apply -f k8s/order-service/deployment-and-service.yaml

# (o) 3.b usar registry (GHCR como ejemplo)
# export IMAGE_REGISTRY=ghcr.io/TU_ORG && docker login ghcr.io
# make ci SERVICE=user-service
# make ci SERVICE=order-service
# kubectl apply -f k8s/user-service/deployment-and-service.yaml
# kubectl apply -f k8s/order-service/deployment-and-service.yaml

# 4) health en cluster
./scripts/minikube_smoke.sh user-service 8000
./scripts/minikube_smoke.sh order-service 8001
USER_URL=$(minikube service user-service --url)
ORDER_URL=$(minikube service order-service --url)
bash scripts/wait-for-http.sh "$USER_URL/health" 60
bash scripts/wait-for-http.sh "$ORDER_URL/health" 60
python healthcheck.py --url "$USER_URL/health" --timeout 30
python healthcheck.py --url "$ORDER_URL/health" --timeout 30

# 5) evidencias
bash scripts/muestra_salidas.sh
kubectl get deploy,svc,pods -o wide | tee .evidence/logs/k8s-overview-$(date +%F-%H%M).txt
```

### 8. Problemas comunes (y soluciones rápidas)

* **El gate SCA falla**: sube el umbral **temporalmente** (solo para demo)
  `SCAN_FAIL_SEVERITY=critical make scan SERVICE=user-service`

* **La imagen no se ve en Minikube**: compila dentro del daemon del cluster

  ```bash
  eval $(minikube docker-env)
  make build SERVICE=user-service
  make k8s-apply SERVICE=user-service    # si tu Makefile lo soporta
  ```

* **`metrics.k8s.io` errors**: ignorables para la demo (addon de métricas).

* **kubectl vs cluster version**: usa el binario de Minikube
  `minikube kubectl -- get pods -A`

* **Windows/PowerShell** (daemon Docker de Minikube):
  `minikube -p minikube docker-env | Invoke-Expression`


### 9. Resumen de targets típicos del Makefile

* `make env SERVICE=...` -> muestra variables (SERVICE, TAG, IMAGE)
* `make dev SERVICE=...` -> build + test local con Compose
* `make build SERVICE=...` -> construye la imagen local
* `make sbom SERVICE=...` -> genera SBOM
* `SCAN_FAIL_SEVERITY=high make scan SERVICE=...` -> SCA + gate (SARIF)
* `make sign SERVICE=...` y `COSIGN_VERIFY=1 make sign SERVICE=...` -> firma/verifica
* `make ci SERVICE=...` / `make pipeline SERVICE=...` -> flujo CI local con push y firma
* `make minikube-up` -> arranca Minikube
* `make k8s-prepare` -> namespace/recursos base (si aplica)
* `make k8s-apply SERVICE=...` -> despliegue K8s del servicio

### 10. Artefacto `.tar` en `artifacts/` 

En el laboratorio no hay un **`.tar` preconstruido** (por ejemplo,  `artifacts/user-service.tar`). Cuando lo tengas y los uses permite:

* Generar **SBOM** sin reconstruir la imagen:

  ```bash
  syft packages docker-archive:artifacts/user-service.tar -o json > artifacts/user-service-sbom.json
  ```
* Ejecutar **SCA**/vulnerabilidades **offline**:

  ```bash
  grype docker-archive:artifacts/user-service.tar -o sarif > artifacts/user-service-grype.sarif
  ```
* **Mover** la imagen entre hosts sin usar un registry.

#### Regenerar el `.tar` (elige una opción)

**A) Desde tu build local**

```bash
docker build -t user-service:MYTAG -f docker/Dockerfile.python-template .
mkdir -p artifacts
docker save user-service:MYTAG -o artifacts/user-service.tar
```

**B) Build dentro de Minikube (sin registry)**

```bash
minikube start --driver=docker
eval $(minikube docker-env)
docker build -t user-service:MYTAG -f docker/Dockerfile.python-template .
mkdir -p artifacts
docker save user-service:MYTAG -o artifacts/user-service.tar
```

**C) Desde un registry (si ya publicaste)**

```bash
docker pull ghcr.io/TU_ORG/user-service:MYTAG
mkdir -p artifacts
docker save ghcr.io/TU_ORG/user-service:MYTAG -o artifacts/user-service.tar
```

> Alternativa:
> `skopeo copy docker://ghcr.io/TU_ORG/user-service:MYTAG docker-archive:artifacts/user-service.tar`

#### Comprobaciones

```bash
tar tf artifacts/user-service.tar | head     # listar contenido
```

#### Nota de firma (Cosign)

* **cosign** firma **referencias en registro** (`ghcr.io/...:tag`), **no** el `.tar` local.
  Para firma/verificación:

  ```bash
  cosign sign ghcr.io/TU_ORG/user-service:MYTAG
  cosign verify ghcr.io/TU_ORG/user-service:MYTAG
  ```

Con se demuestra el **ciclo completo Dev -> Sec -> Ops** en local, con **artefactos auditables** y **controles de seguridad**.
