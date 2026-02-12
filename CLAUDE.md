# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DevOps-News is a demonstration monorepo for Kubernetes training. It consists of four services: a Flask API backend, an Nginx static frontend (with reverse proxy), a shell-based cleaner job, and a Redis datastore.

## Build & Run

```bash
# Build and start all services
docker compose up --build

# Rebuild a single service
docker compose up --build backend

# Run the cleaner manually (one-shot)
docker compose run --rm cleaner
```

The app is accessible at http://localhost:8080. The backend is not exposed directly — it's reachable only through the Nginx reverse proxy at `/api/`.

## Architecture

**Request flow:** Browser → Nginx (:80, exposed as :8080) → `/api/*` proxied to → Flask backend (:5000) → Redis

- **Frontend** (`src/frontend/`): Nginx serves `index.html` and reverse-proxies `/api/` to `http://backend:5000/`. The trailing slash in `proxy_pass` strips the `/api` prefix, so `/api/news` hits `/news` on the backend.
- **Backend** (`src/backend/`): Single-file Flask app (`app.py`). All data stored in a Redis list under key `devops_news` as JSON strings. Each entry has `title`, `content`, `timestamp` fields.
- **Cleaner** (`src/cleaner/`): One-shot shell script using `redis-cli`. Iterates the Redis list from tail to head and removes entries older than `MAX_AGE_SECONDS`. Designed to run as a Kubernetes CronJob.
- **Redis**: Official `redis:alpine` image with password auth. Data persisted via `redis_data` named volume.

## Environment Variables

All services sharing Redis access use the same three variables:

| Variable | Default | Used by |
|---|---|---|
| `REDIS_HOST` | `localhost` | backend, cleaner |
| `REDIS_PORT` | `6379` | backend, cleaner |
| `REDIS_PASSWORD` | (none) | backend, cleaner |
| `MAX_AGE_SECONDS` | `3600` | cleaner only |

In docker-compose, `REDIS_PASSWORD` is set to `supersecret`.

## API Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness probe — pings Redis, returns 200 or 503 |
| GET | `/news` | Returns all news as JSON array |
| POST | `/news` | Creates a news entry (`{"title": "...", "content": "..."}`) |

Through the frontend proxy, these are accessed as `/api/health`, `/api/news`.
