# web-detect

Self-hosted web page change monitor using [urlwatch](https://urlwatch.readthedocs.io/) and [Ofelia](https://github.com/mcuadros/ofelia), with notifications via [Apprise](https://github.com/caronc/apprise).

## How it works

```
Ofelia (cron scheduler)
  └─ exec every 5 min  → urlwatch --urls /config/urls-fast.yaml
  └─ exec every hour   → urlwatch --urls /config/urls-hourly.yaml
  └─ exec every day    → urlwatch --urls /config/urls-daily.yaml
                                  ↓ (if changes detected)
                         run-check.sh → apprise → your notification channel
```

- **urlwatch** fetches each configured URL, applies a per-job filter pipeline (CSS, XPath, regex, jq, …), and diffs the result against a local cache.
- **Ofelia** calls urlwatch on the scheduled tiers via `docker exec`.
- **run-check.sh** captures urlwatch output and forwards it to Apprise only when something changed.
- Three schedule tiers keep fast-moving and slow-moving pages separate so notifications stay relevant.

---

## Project layout

```
web-detect/
├── Dockerfile               # urlwatch + apprise image
├── docker-compose.yml       # urlwatch service + Ofelia scheduler
├── .env.example             # environment variable template
├── config/
│   ├── urlwatch.yaml        # global settings (display, reporters, job defaults)
│   ├── urls-fast.yaml       # jobs checked every 5 minutes
│   ├── urls-hourly.yaml     # jobs checked every hour
│   └── urls-daily.yaml      # jobs checked every day at 07:00
└── scripts/
    └── run-check.sh         # check runner + Apprise notification bridge
```

---

## Quick start

### 1. Configure notifications

```bash
cp .env.example .env
```

Edit `.env` and set `APPRISE_URLS` to one or more Apprise notification URLs:

```env
APPRISE_URLS=telegram://BotToken/ChatID
```

Multiple destinations are space-separated:
```env
APPRISE_URLS=telegram://BotToken/ChatID discord://WebhookID/WebhookToken
```

See the [Apprise documentation](https://github.com/caronc/apprise#supported-notifications) for all supported services.

### 2. Make the run script executable

```bash
chmod +x scripts/run-check.sh
```

### 3. Add URLs to watch

Edit one of the tier files to add your own jobs.  
Each job is separated by `---` and requires a `name`, a `url`, and `tags: [<tier>]`.

```yaml
# In config/urls-hourly.yaml
---
name: "My site – news section"
url: "https://mysite.example.com/news"
tags: [hourly]
filter:
  - css: "section.news-list"
  - html2text
  - strip
```

See [Testing filters locally](#testing-filters-locally) to verify your filter pipeline before deploying.

### 4. Build and start

```bash
docker compose up -d --build
```

Check that both services are running:

```bash
docker compose ps
```

### 5. Trigger a manual run

```bash
# Run the fast tier immediately (useful for testing)
docker exec web-detect-urlwatch /scripts/run-check.sh fast
```

---

## Adding URLs

1. Decide which tier fits the page:

| Tier | File | Checked | Use when |
|------|------|---------|----------|
| `fast` | `config/urls-fast.yaml` | Every 5 min | Live prices, stock, status pages |
| `hourly` | `config/urls-hourly.yaml` | Every hour | News, releases, dashboards |
| `daily` | `config/urls-daily.yaml` | Daily at 07:00 | Policies, job boards, docs |

2. Add a job block (separated by `---`) to the right file.
3. Restart is **not required** — the next scheduled run picks up the new job automatically.

---

## Filter pipeline

urlwatch applies filters in sequence to the fetched content before diffing.  
Combine built-in filters using a list under `filter:`.

| Filter | Purpose | Example |
|--------|---------|---------|
| `css: "selector"` | Extract HTML elements by CSS selector | `css: "div.price"` |
| `xpath: "/path"` | Extract by XPath expression | `xpath: "//h1"` |
| `html2text` | Convert HTML to plain text | `- html2text` |
| `jq: ".field"` | Extract from JSON response | `jq: ".data.price"` |
| `grep: "pattern"` | Keep only matching lines | `grep: "v[0-9]"` |
| `grepi: "pattern"` | Remove matching lines | `grepi: "advertisement"` |
| `re.sub: "pattern"` | Replace/remove via regex | `re.sub: '\s+'` |
| `strip` | Remove leading/trailing whitespace | `- strip` |
| `sort` | Sort lines (eliminates reorder noise) | `- sort` |
| `shellpipe: "cmd"` | Arbitrary shell transformation | `shellpipe: "awk ..."` |

Chains are written as a YAML list:

```yaml
filter:
  - css: "table.prices tbody tr"
  - html2text
  - grep: "EUR"
  - strip
```

---

## Testing filters locally

Before deploying a new job, test its filter pipeline without waiting for Ofelia:

```bash
# Test filter output for the first job in urls-hourly.yaml
docker exec web-detect-urlwatch urlwatch \
  --urls /config/urls-hourly.yaml \
  --cache /cache/cache-hourly.db \
  --config /config/urlwatch.yaml \
  --test-filter 1

# Test by URL (must match exactly)
docker exec web-detect-urlwatch urlwatch \
  --urls /config/urls-daily.yaml \
  --cache /cache/cache-daily.db \
  --config /config/urlwatch.yaml \
  --test-filter "https://example.com/legal/tos"
```

---

## Changing schedules

Schedules are defined as Ofelia labels on the `urlwatch` service in `docker-compose.yml`.  
Edit the relevant `ofelia.job-exec.*.schedule` label and redeploy:

```bash
docker compose up -d
```

Standard 5-field cron and Ofelia shorthands are both supported:

```yaml
# Every 10 minutes
ofelia.job-exec.check-fast.schedule: "@every 10m"

# At 08:30 every weekday
ofelia.job-exec.check-daily.schedule: "30 8 * * 1-5"
```

---

## Viewing logs

```bash
# Ofelia scheduler logs (shows when each job fires)
docker compose logs ofelia

# urlwatch container logs (shows script output and errors)
docker compose logs urlwatch

# Follow both in real time
docker compose logs -f
```

---

## Backup and recovery

| What | Where | How to back up |
|------|-------|---------------|
| Job configuration | `config/` directory | Version control or regular file copy |
| Change cache | Docker volume `web-detect_cache` | `docker run --rm -v web-detect_cache:/cache alpine tar czf - /cache` |

To rebuild from scratch (re-initialise cache):

```bash
docker compose down -v   # removes the cache volume
docker compose up -d
```

The first run after a cache reset treats every job as "new" and sends one notification per job.

---

## Upgrading

```bash
docker compose pull      # fetch latest Ofelia image
docker compose build     # rebuild urlwatch image with latest pip packages
docker compose up -d
```
