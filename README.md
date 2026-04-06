# Daily Dose

A zero-cost, offline-first iOS application that delivers a single, randomly selected open-access scientific article from PubMed every morning.

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│  PubMed E-utils │────▶│ GitHub Action │────▶│ GitHub Pages │────▶│  iOS App     │
│  (PMC Database) │     │ (Python Cron) │     │ (today.json) │     │ (SwiftUI)   │
└─────────────────┘     └──────────────┘     └──────────────┘     └─────────────┘
```

**Data Flow:**
1. **Daily at Midnight UTC** — A GitHub Actions cron job runs `backend/fetch_article.py`
2. **Fetch** — The script queries PubMed Central for a random open-access article from the last 5 years
3. **Parse & Validate** — XML is converted to a structured JSON payload with Markdown-formatted text, figure URLs, and table HTML
4. **Deploy** — The validated `today.json` is force-pushed to the `gh-pages` branch, served by GitHub Pages CDN
5. **Sync** — The iOS app fetches `today.json` on foreground, caches locally with SwiftData

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS App | Swift, SwiftUI, SwiftData, TextKit 2 (iOS 17+) |
| Backend | Python 3.12, xml.etree.ElementTree |
| CI/CD | GitHub Actions (scheduled cron) |
| Hosting | GitHub Pages (static CDN) |

## Setup

### Backend (Local Testing)
```bash
cd backend
pip install -r requirements.txt
NCBI_EMAIL="your@email.com" python fetch_article.py
```

### iOS App
1. Open Xcode and create a new project
2. Add all files from `ios-app/DailyDose/` to the project
3. Set deployment target to iOS 17.0
4. Build and run

### GitHub Actions
1. Add your email as a repository secret: `NCBI_EMAIL`
2. Configure GitHub Pages to deploy from the `gh-pages` branch
3. The workflow runs automatically at midnight UTC, or trigger manually via `workflow_dispatch`

## License

MIT
