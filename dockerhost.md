# Dockerhost Infrastructure Documentation

## Overview
This host (`dockerhost`) runs a suite of containerized applications managed via **Docker Compose**.
The configuration is consolidated in `/root/docker-compose.yml`.

## Core Services

### 1. Infrastructure Management
- **Orchestration:** Docker Compose
- **GUI Management:** Portainer
  - **URL:** `https://localhost:9443` (Self-signed certificate)
  - **Volume:** `portainer_data` (Persisted locally)
- **Automatic Updates:** Watchtower
  - **Schedule:** Checks every 24 hours.
  - **Configuration:** Requires `DOCKER_API_VERSION=1.53` to prevent boot loops with the host's Docker engine (v29.2.1).
  - **Scope:** Updates all containers, with specific focus on `ivantsov.tech` via labels.

### 2. Applications
- **Finance Report:**
  - **URL:** `http://localhost:3020`
  - **Image:** `ghcr.io/exploitacious/finance-report:latest`
  - **Data Path:** `/root/finance-report-data` (Mapped to `/app/data`)
  - **Token Path:** `/root/finance-report-tokens` (Mapped to `/app/tokens`)
  - **Env File:** `/root/finance-report-tokens/.env`
- **Personal Website (ivantsov.tech):**
  - **URL:** `http://localhost:3010`
  - **Image:** `ghcr.io/exploitacious/ivantsov.tech:latest`
  - **Update Policy:** Explicitly enabled for Watchtower updates via labels.

## Deployment & Maintenance

### Managing the Stack
All services are defined in `/root/docker-compose.yml`.

**Start/Update Stack:**
```bash
docker compose -f /root/docker-compose.yml up -d
```

**Restart Specific Service:**
```bash
docker compose -f /root/docker-compose.yml restart finance-report
```

**View Logs:**
```bash
docker compose -f /root/docker-compose.yml logs -f [service_name]
```

## Critical Configuration Notes
1. **Watchtower Compatibility:** The `watchtower` container MUST have the environment variable `DOCKER_API_VERSION=1.53` set. Without this, it fails to communicate with the host Docker daemon (API v1.53) and enters a boot loop due to client version mismatch (1.25 vs 1.44+).
2. **Port Mappings:**
   - `:3010` -> Website (HTTP)
   - `:3020` -> Finance Report (HTTP)
   - `:8000` -> Portainer (HTTP - Redirect)
   - `:9443` -> Portainer (HTTPS - UI)
