# Browser Use for coding agents — portable, self-contained

You are a coding session (cloud or local) that may need to act on the **web**: create
credentials on a dashboard, sign up for a service, read/act inside an account, or
reproduce and debug a bug through a real browser — things that have no CLI or API.
This document makes you fully capable of that with **no dependency on any other local
file**. Read it once, then use the `bu` and `bu-drive` commands.

Everything runs on **Browser Use Cloud** (managed cloud Chrome with stealth, residential
proxies, persistent logged-in profiles, live view). Two tools wrap it:
- **`bu`** — hosted agent runs (give a goal, their LLM drives) and bare cloud browsers.
- **`bu-drive`** — YOU drive a cloud browser over CDP, step by step, while a human
  watches live. For debugging / ablation.

---

## 0. Bootstrap (fresh environment)

If `bu` is not on PATH, install the bundle (idempotent):

```sh
BROWSER_USE_API_KEY=bu_...  sh bootstrap.sh      # from the bundle dir
# or if the key is already in the environment:
sh bootstrap.sh
export PATH="$HOME/.local/bin:$PATH"
bu models                                        # verify
```

The bundle (`bu`, `bu-drive`, `config.json`, `bootstrap.sh`, this doc) carries **no
secret**. The only secret is `BROWSER_USE_API_KEY` (starts `bu_`, travels in the
`X-Browser-Use-API-Key` header); never hard-code, print, or commit it. bootstrap.sh
sources it in this order: an existing `~/.agents/browser/credentials/api_key` file →
the `BROWSER_USE_API_KEY` env var → **Doppler** (`shared-vendors/prd`, override with
`BU_DOPPLER_PROJECT`/`BU_DOPPLER_CONFIG`). So a cloud session needs EITHER
`BROWSER_USE_API_KEY` in its env, OR Doppler access (a `DOPPLER_TOKEN` service token
scoped to shared-vendors/prd) — the latter keeps the raw key out of every cloud env
and rotates in one place. **Profiles are account-scoped on Browser Use's
side**, so any session with the same key sees the same synced logins — the two profile
aliases (`konstant`, `gmail`) in `config.json` work everywhere the key does.

---

## 1. Which tool for the job

| Need | Tool |
|-|-|
| Fuzzy multi-step errand, unattended ("sign up, create an API key, report it") | `bu run` (hosted agent) |
| Deterministic flow, or you must drive precisely / delicately | `bu-drive` (you drive over CDP) |
| Reproduce / ablate / fix a bug with a human watching | `bu-drive` |
| A bare browser to attach your own Playwright/Puppeteer over CDP | `bu browser start` → `cdp_url` |

`bu run`'s driving LLM is a black box you don't step through. `bu-drive` makes every
move yours and observable. Pick `bu-drive` whenever the point is to *understand*, not
just to *complete*.

---

## 2. Identity routing — act as the right logged-in person

Two synced identities exist: **`konstant`** (Konstant/work: konstant.cloud, Slack,
Cloudflare Access, Vercel, Doppler, banking/benefits) and **`gmail`** (personal:
ahelfgott@gmail.com and personal portals).

```sh
bu which <domain>          # which profile has a session for a site (ranked)
bu run "..." --for <domain>   # auto-pick the profile; REFUSES a tie
bu run "..." --profile konstant   # or name it explicitly
```

**Overlap is real**: both identities carry google.com, vercel.com, slack.com, etc.
(the local browser had both logged in at sync). So the *domain* can't pick the identity
— the *task intent* does: work/company → `konstant`, personal → `gmail`. `--for`
deliberately errors on a tie so account-critical runs get an explicit `--profile`. If a
run that should be logged in reports NOT LOGGED IN, the session expired — a human must
re-run `bu profile sync` locally (it can't be done from a cloud box; passkeys/logins
live on their machine).

---

## 3. Pick the model — the real lever (`--model`, `--effort`)

The browser-driving model is chosen per run. Match it to difficulty and reversibility.
A cheap model misclicking on a payment or a security setting is false economy;
overpaying to read a value is waste.

| Task shape | `--model` | `--effort` |
|-|-|-|
| Read / navigate / look up / download / check status | `gpt-5.6-luna` (default) or `kimi-k3` (cheapest) | `low` / none |
| Multi-step: form, create an API key on a familiar dashboard, sign up, post | `gpt-5.6-luna` | `medium` |
| Delicate/high-stakes: payments, account/security/billing changes, irreversible, heavy anti-bot, ambiguous UI | `gpt-5.6-sol` or `claude-sonnet-5` | `high` / `xhigh` |

Full model list: `gpt-5.5`, `gpt-5.6`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`,
`claude-opus-4.7/4.8/5`, `claude-fable-5`, `claude-sonnet-5`, `gemini-3-flash`,
`gemini-3.1-pro`, `gemini-3.5-flash`, `gemini-3.6-flash`, `grok-4.5`, `glm-5.2`,
`kimi-k3`, `minimax-m3`. Effort (`--effort none|low|medium|high|xhigh|max`) maps per
family: gpt→`reasoning.effort`, claude→`output_config.effort`, gemini→
`thinkingConfig.thinkingLevel`. `kimi-k3`, `grok-4.5`, `glm-5.2`, `minimax-m3`,
`claude-fable-5` do NOT accept effort (it no-ops). A trivial run costs ~$0.004 on luna.

---

## 4. `bu` command reference

```sh
bu run "task" [--model M] [--effort E] [--profile NAME | --for DOMAIN] \
              [--max-cost USD] [--sensitive] [--notify] [--no-wait]
bu continue <session-id> "next step"   # resume SAME browser after a human took over
bu watch <run-id> [--notify]           # attach to a --no-wait run
bu status|get|cancel <run-id>
bu which <domain> [--refresh]          # profile routing
bu files <workspace-id> --download DIR # run outputs (URLs expire in 60s)
bu browser start|list|stop <id>|stop --all   # bare cloud Chrome (CDP); STOP ends billing
bu profile list|create NAME|alias NAME ID     # (sync is local-only)
bu models | bu config | bu ledger
```

Writing a good task decides success as much as the model: give the exact start URL, the
concrete action, and exactly what to report. Be explicit about forks ("if X then Y,
else stop and report"). The stop-for-human clause is auto-appended (disable with
`--raw-task`).

---

## 5. `bu-drive` — you drive, a human watches

The cloud browser is **durable server-side**, so these stateless calls compose into one
session; only your CDP connection is ephemeral. Screenshots are written to files — read
them to actually see the page.

```sh
bu-drive start --profile konstant --url https://…   # prints live_url for the human to WATCH
bu-drive shot                       # screenshot -> file
bu-drive eval '<js>'                # inspect/ablate: read state, poke a variable, mutate DOM
bu-drive click "text=Save"          # Playwright selector syntax; --logs adds console+network
bu-drive fill "#email" "x@y.z"      # mutating verbs auto-screenshot
bu-drive press Enter | bu-drive url <U> | bu-drive text [sel] | bu-drive info
bu-drive stop                       # ENDS BILLING — always stop when done
```

Selectors use Playwright syntax: `text=…`, `role=button[name=…]`, `#id`, `.class`,
`xpath=…`. Debug loop: navigate as the right identity → `shot` → `eval` to change one
variable → `--logs` to see which console error / failed request a click produced.

---

## 6. Rules (each learned from the docs or paid for in testing)

1. **A bare browser and a driven browser bill until explicitly stopped.** `bu browser
   stop <id>` / `bu browser stop --all` / `bu-drive stop`. Dropping the CDP connection
   or a run finishing does NOT stop a standalone/driven browser. Never end a session
   with one you started still running.
2. **Live-view URLs are credential-grade** — whoever holds one controls the browser.
   Give them to the human (that's the point); never write them to files, commits, logs,
   or artifacts.
3. **Credential-creating runs use `--sensitive`** — keeps the result out of the shared
   ledger. Print it once, store it where it belongs, don't echo it again.
4. **Never put passwords in a task prompt.** Logged-in state comes from profiles.
5. **Human-in-the-loop is by instruction** (auto-appended), not an automatic signal.
   On a stop: hand the human the live-view URL, then `bu continue <session-id> "…"`.
6. **Watch your own runs.** The dispatching session supervises; there is no concierge.
7. **Cap experiments** with `--max-cost`. Confirm with the human before financial or
   security account changes, even when a session exists — a logged-in profile can act
   on those accounts.
8. **v4 only** for agent runs (v2 is far less accurate). `bu` uses the SDK's v3
   namespace internally for browsers/profiles — that's expected, not a mistake.

---

## 7. Raw API fallback (no SDK / debugging)

Base `https://api.browser-use.com/api/v4`, header `X-Browser-Use-API-Key: bu_…`.
- `POST /runs` `{"task","model","browserSettings":{"profileId":…},"modelParams":{…},"maxCostUsd":…}` → `{id, sessionId, ...}`
- `GET /runs/{id}/status` → `{status}` (terminal: `completed|failed|cancelled`)
- `GET /runs/{id}` → full summary incl. `result` (always a string — ask for JSON in the
  prompt and parse client-side; there is no output_schema param)
- `GET /runs/{id}/events?after=N` → paginated events (`events`, `nextAfter`, `hasMore`);
  a `browser.ready`-ish event carries the live-view URL
- `POST /runs/{id}/cancel`
- Standalone browser is the **v3** surface: `POST /browsers` → `{cdpUrl, liveUrl}`;
  **stop billing** with `PATCH /browsers/{id}` `{"action":"stop"}` (SDK: `browsers.stop`).
- Docs (kept current — prefer over this file if they conflict):
  https://docs.browser-use.com/cloud/llms.txt · vibecoding · llms-full.txt ·
  models · thinking-levels · guides/{secrets,authentication,profile-sync,1password,2fa}
