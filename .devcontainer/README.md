# LearnHarness in a Codespace

This fork runs LearnHarness in one long-lived GitHub Codespace, so any device with a browser and a GitHub sign-in can use it. Nothing needs installing on the device.

## What happens automatically

- **On create:** installs packages (`npm ci`, without the Electron desktop runtime), restores your learning data from the backup repo, and builds the app.
- **On every start:** starts the app on port **3100** and starts the backup loop. If the code changed since the last build, it rebuilds first, which takes about a minute.
- **Every 5 minutes:** if the learning data changed, it commits and pushes it to your private backup repo.

| What | Where |
| --- | --- |
| Learning data (chats, graph, settings, prompts) | `/workspaces/.lh-data`, backed up |
| Keys and sign-ins (`auth.json`, `*-credentials.json`) | `/workspaces/.lh-auth`, **never** backed up |
| Logs | `/workspaces/.lh-logs/server.log`, `/workspaces/.lh-logs/data-sync.log` |

Both data folders sit outside the git checkout and survive stopping and starting the codespace. A codespace that is **deleted** loses `.lh-auth` (you sign in again) and keeps your learning data only through the backup.

The app runs in production mode (`npm run build` + `npm start`). `next dev` blocks pages opened through the `*.app.github.dev` address. `npm start` prints a warning about `output: standalone`; it is harmless here.

## One-time setup

### 1. The backup repo

Create a **private**, empty repo named `learnharness-data` under your account. To use another name, set the `LH_DATA_REPO` secret to `owner/name`.

### 2. Codespaces secrets

Add these at **GitHub → Settings → Codespaces → Secrets → New secret** (`https://github.com/settings/codespaces`). Give each one access to this fork (**Repository access → `<you>/learnharness`**). Secrets reach a codespace when it starts, so restart a running codespace after you add one.

| Secret | Required | What it is |
| --- | --- | --- |
| `LH_DATA_TOKEN` | For backups | A **fine-grained personal access token** (`https://github.com/settings/personal-access-tokens/new`). Resource owner: you. Repository access: **Only select repositories → `learnharness-data`**. Permissions: **Contents: Read and write**. Choose a long expiry and note when it ends: an expired token stops backups. The codespace's own `GITHUB_TOKEN` cannot reach the backup repo, so this token is needed. |
| `LH_DATA_REPO` | No | `owner/name` of the backup repo. Default: `<your username>/learnharness-data`. |
| Model provider key | One way to use models | The app reads the same names it shows in Settings → Providers, for example `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `GEMINI_API_KEY`. The full list is in `src/core/auth-keys.ts`. |
| Search key | No | One of `TAVILY_API_KEY`, `BRAVE_API_KEY`, `EXA_API_KEY`, `FIRECRAWL_API_KEY` or `OLLAMA_API_KEY`, for background web research. |
| `DEEPGRAM_API_KEY` | No | Dictation. |

A key set as a secret takes precedence over a key saved in the app's Settings. Keys saved in Settings go to `/workspaces/.lh-auth/auth.json` and stay in that codespace.

**If `LH_DATA_TOKEN` is missing or wrong,** the app still runs but nothing is backed up. The start output and `/workspaces/.lh-logs/data-sync.log` then show a line starting with `BACKUP OFF`.

### 3. Create the codespace

On the fork: **Code → Codespaces → ⋯ → New with options**, pick 4-core, then **Create codespace**. When the build finishes, the **Ports** tab shows *LearnHarness (3100)*. Open its address (`https://<name>-3100.app.github.dev`) on any device where you are signed in to GitHub.

Use this one codespace from every device. Running two at once means two copies of the app writing to the same backup.

### 4. Recommended GitHub settings

At `https://github.com/settings/codespaces`:

- **Default idle timeout:** raise it (the maximum is 240 minutes), so a lesson isn't cut off when you pause.
- **Default retention period:** a stopped codespace is deleted after this many days. 30 is both the default and the maximum, so open the codespace at least once a month. The backup protects your learning data either way; only keys saved in the app and sign-ins would need redoing.

Keep port 3100 **private**, which is the default. The app has no login of its own; a public port would expose your keys and data to anyone with the link.

## Signing in with ChatGPT

ChatGPT sign-in sends its result back to `http://localhost:1455/auth/callback`. In a browser-only codespace, `localhost` means *your device*, not the codespace, so the last step of sign-in fails with a "can't connect" page. To finish:

1. Copy the full address of that failed page (it starts with `http://localhost:1455/auth/callback?code=…`).
2. In the codespace terminal, run `curl "<the address you copied>"`.

The sign-in then completes inside the codespace. GitHub Copilot and Grok use device codes and work without this step. API keys set as secrets avoid sign-in altogether.

This was worked out from the code, not tested in a real codespace.

## Everyday commands (codespace terminal)

```bash
tail -f /workspaces/.lh-logs/server.log      # app output
tail -f /workspaces/.lh-logs/data-sync.log   # backup activity
bash .devcontainer/data-sync.sh once         # back up right now
pkill -f "next start"; bash .devcontainer/post-start.sh   # restart the app
```

Stopping the codespace can lose up to 5 minutes of changes that haven't been backed up yet. Run `data-sync.sh once` before stopping if that matters.

## Restoring on a new codespace

If `/workspaces/.lh-data` is empty when the codespace starts, it is filled from the backup repo automatically. If the folder already has data *and* the backup repo has history, the script won't merge the two. It logs `BACKUP OFF` and leaves both alone; move one aside and run `bash .devcontainer/data-sync.sh restore`.
