# Patent Creation Assistant (MVP)

This MVP turns plain-text idea inputs into:
- A heuristic “patent worthiness” screening (not legal advice)
- A US provisional/utility-style drafting scaffold (print/export-ready HTML)
- Mermaid block diagram source for FIG. 1
- Optional prior-art search using Google Custom Search with `site:uspto.gov` queries

## Run locally

1. Install Ruby gems:
   - `bundle install`
2. (Optional) Configure prior-art search:
   - Set `GOOGLE_API_KEY`
   - Set `GOOGLE_CSE_ID` (Google Custom Search engine id / cx)
3. Start the server:
   - `bundle exec rackup -p 4567`
4. Open:
   - `http://localhost:4567/`

## Export to PDF

Use the UI button **Print Draft** and save as PDF in your browser’s print dialog.

## Rate limiting + monitoring

To keep the app safe for free hosting, it includes basic in-memory per-IP rate limiting for `POST /api/*`:
- `RATE_LIMIT_MAX` (default `60`) requests per `RATE_LIMIT_WINDOW_SECONDS` (default `60`)
- `GENERATE_RATE_LIMIT_MAX` (default `20`) requests per `GENERATE_RATE_LIMIT_WINDOW_SECONDS` (default `60`)

The app emits structured JSON logs to stdout for request monitoring (method/path/status/duration/ip/requestId).

Optional endpoint for usage stats (only enabled if `ENABLE_USAGE_ENDPOINT=1`):
- `GET /api/usage`

## Notes / limitations

- This tool is a writing scaffold and heuristic screen; it does **not** determine legal novelty, patentability, or compliance with USPTO requirements.
- Prior-art search results depend on your Google Custom Search configuration.

## Deploy for free (Render)

Render offers a free-tier plan for small services (availability can vary over time/region).

### Step 1: Create a GitHub repo
1. Create a new **empty** repository on GitHub (you’ll push your code shortly).
2. Decide on a name like `patent-creation-assistant`.

### Step 2: Push code to GitHub (you do this part)
I can’t push to your GitHub directly from here, but you can run:
```bash
cd "/Users/nishant/cursor ai project"
git init
git add .
git commit -m "Initial MVP"
git branch -M main
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

If you prefer, tell me your repo URL and whether you want `main` or `master`, and I’ll tailor the commands.

### Step 3: Create the Render Web Service
1. Sign up for Render (free).
2. New Web Service -> connect GitHub -> select your repo.
3. Service details:
   - **Build Command:** `bundle install`
   - **Start Command:** `bundle exec rackup -p $PORT`
   - **Instance Type:** free tier (if offered)
4. Add Environment Variables (optional):
   - `ENABLE_USAGE_ENDPOINT=1` (optional)
   - `GOOGLE_API_KEY` / `GOOGLE_CSE_ID` (only if you want automated prior-art search)
5. Create service and wait for deployment.

