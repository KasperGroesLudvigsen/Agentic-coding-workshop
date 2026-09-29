# OpenCode setup guide for workshop participants

Sep 29, 2026 · @Kasper

Participants run one script. It installs OpenCode and connects it to the workshop's OpenRouter endpoint and model. Setup takes about five minutes and needs no admin rights. The scripts were tested against OpenCode 1.18.33, the latest release as of today.

## Before the workshop (facilitators)

Fill in the values at the top of both scripts, then hand them out at least a week ahead so problems surface before Day 1.

| Setting in the script | Linux name / Windows name | What to put there |
| --- | --- | --- |
| Endpoint | `OPENROUTER_BASE_URL` / `$OpenRouterBaseUrl` | The API base URL, ending in `/api/v1`. The public endpoint is `https://openrouter.ai/api/v1`. OpenCode adds `/chat/completions` itself. |
| API key | `OPENROUTER_API_KEY` / `$OpenRouterApiKey` | Leave the placeholder to make the script ask each participant for their own key (recommended), or paste a shared key. |
| Model | `OPENCODE_MODEL` / `$OpenCodeModel` | The main coding model's OpenRouter ID, for example `qwen/qwen3.8-27b`. Don't include the `openrouter/` prefix; the script adds it. |
| Small model | `OPENCODE_SMALL_MODEL` / `$OpenCodeSmallModel` | The model for light background tasks such as naming sessions, for example `qwen/qwen3.6-35b-a3b`. Leave the placeholder to use the main model for these too. |
| Precision | `OPENROUTER_PRECISIONS` / `$OpenRouterPrecisions` | Set to `bf16,fp16`. OpenRouter then only routes to providers serving the model at those precisions, which matches what you'll self-host. |
| Version | `OPENCODE_VERSION` / `$OpenCodeVersion` | Pin one version, for example `1.18.33`, so everyone runs the same build. Empty means latest. |

**Check that providers exist at bf16/fp16 before choosing models.** You can see a model's providers and their precision on its OpenRouter page. As of 29 September 2026, `qwen/qwen3.8-27b` has one bf16 provider (DeepInfra). `qwen/qwen3.6-35b-a3b` has none: every provider serves fp8 or lower, so with this filter its requests would fail. Until that changes, leave the small-model placeholder so the main model handles both. With one provider there's no fallback, so load-test with about 40 parallel sessions before the workshop.

1. **Create one API key per participant** in OpenRouter under Settings → API keys. Set a credit limit on each key. A leaked key is then capped and can be revoked on its own.
2. **Set OpenRouter's privacy settings** for the organization: turn off providers that train on your data, and prefer zero-data-retention providers. If the internal stack must stay on open models, use OpenRouter's model and provider restrictions for the organization. The script's allow-list only hides other models in OpenCode; it doesn't block them.
3. **Check the network.** Participants need HTTPS access to `github.com` (download), `opencode.ai` (Linux installer) and your OpenRouter endpoint. `models.opencode.ai` (the model catalogue) helps but isn't required. Corporate proxies are the most common blocker.
4. **Distribute the two scripts** (`setup-opencode.sh`, `setup-opencode.ps1`) through a channel participants trust, such as an internal Git repo or file share, and send each participant their key separately.
5. **Do a dry run** on one Linux and one Windows machine from the client's standard image.

## Linux

The same steps work in WSL on Windows (Ubuntu or another distribution). You need `curl` and `tar`, which most distributions include.

1. **Save the script** `setup-opencode.sh` somewhere you can find it, for example your home folder.
2. **Open a terminal** in that folder and run:

   ```bash
   bash setup-opencode.sh
   ```
3. **Paste your API key** when asked and press Enter. The input is hidden, so nothing appears as you paste.
4. **Wait for the "OpenCode is installed and configured" message.** The script installs OpenCode in `~/.opencode/bin`, adds it to your PATH, and writes the settings to `~/.config/opencode/`.
5. **Open a new terminal** so the updated PATH takes effect, then go to *Check that it works* below.

## Windows

This installs OpenCode natively on Windows 10 or 11, with no admin rights and no Node.js. OpenCode recommends WSL for the best experience. If you already use WSL, follow the Linux steps inside it instead.

1. **Install Git for Windows** if you don't have it yet. You need it in the workshop, and OpenCode uses it too:

   ```powershell
   winget install --id Git.Git -e
   ```
2. **Save the script** `setup-opencode.ps1`, for example in your Downloads folder.
3. **Open PowerShell** in that folder. In File Explorer, go to the folder, type `powershell` in the address bar and press Enter.
4. **Run the script:**

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-opencode.ps1
   ```

   `-ExecutionPolicy Bypass` applies to this one run only. It doesn't change your system settings.
5. **Paste your API key** when asked and press Enter. The input is hidden. In the classic console window, right-click to paste; in Windows Terminal, Ctrl+V works.
6. **Wait for the "OpenCode is installed and configured" message.** The script installs `opencode.exe` in `%USERPROFILE%\.opencode\bin`, adds that folder to your user PATH, and writes the settings to `%USERPROFILE%\.config\opencode\`.
7. **Close PowerShell and open a new window** so the updated PATH takes effect. Windows Terminal is recommended. Then go to *Check that it works* below.

## Check that it works

All three checks should pass before the workshop. The commands are the same on Linux and Windows.

1. **OpenCode is installed.** This prints a version number, for example `1.18.33`:

   ```bash
   opencode --version
   ```
2. **Only the workshop models are available.** This should list only the main model and, if set, the small model, each as `openrouter/<model ID>`:

   ```bash
   opencode models
   ```
3. **The model answers.** This sends one short prompt to the endpoint and should reply with `ready`:

   ```bash
   opencode run "Reply with the single word: ready"
   ```

Then try it for real. Go to a project folder and start the interactive app:

```bash
cd path/to/a/project
opencode
```

Type a question about the code and press Enter. Type `/models` to confirm the workshop model is selected, and `/exit` to quit.

## What the script configures

The script writes two files to `~/.config/opencode/`. On Windows that's `%USERPROFILE%\.config\opencode\`.

- **`openrouter.key`** holds only the API key, readable only by you. Keeping the key out of the settings file means you can share settings (for example in a screen share) without exposing it.
- **`opencode.json`** holds the settings. An existing `opencode.json` or `opencode.jsonc` is renamed with a `.bak-<timestamp>` suffix first.

This is the settings file with a separate small model set. If the small model is left as a placeholder, `small_model` points to the main model and only one model entry is written.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openrouter/<model ID>",
  "small_model": "openrouter/<small model ID>",
  "enabled_providers": ["openrouter"],
  "provider": {
    "openrouter": {
      "options": {
        "baseURL": "<endpoint URL>",
        "apiKey": "{file:~/.config/opencode/openrouter.key}"
      },
      "models": {
        "<model ID>": {
          "options": {
            "provider": {
              "quantizations": ["bf16", "fp16"],
              "data_collection": "deny"
            }
          }
        },
        "<small model ID>": {
          "options": {
            "provider": {
              "quantizations": ["bf16", "fp16"],
              "data_collection": "deny"
            }
          }
        }
      },
      "whitelist": ["<model ID>", "<small model ID>"]
    }
  },
  "share": "disabled",
  "autoupdate": false
}
```

| Setting | What it does | Why it's set |
| --- | --- | --- |
| `model` | The model OpenCode uses for coding | Everyone works with the same model |
| `small_model` | The model for background tasks such as naming sessions | A smaller model is faster and cheaper for these tasks |
| `enabled_providers` | Turns off every provider except OpenRouter | No calls to other services, including OpenCode's own free models |
| `baseURL` | Where requests go | Your endpoint; OpenCode adds `/chat/completions` |
| `apiKey` | Reads the key from `openrouter.key` | Keeps the key out of the settings file |
| `models` | Registers each model ID with its routing rules | Works even if a model isn't in OpenCode's built-in catalogue |
| `quantizations` | OpenRouter only uses providers serving the model at bf16 or fp16 | Participants see the same precision you'll self-host, not a cheaper quantized version |
| `data_collection: deny` | OpenRouter skips providers that may store or train on prompts | Keeps workshop code out of provider datasets |
| `whitelist` | Hides all other OpenRouter models | Participants can't pick another model by mistake |
| `share` | Turns off session sharing | Sessions, and the code in them, can't be published to a public link |
| `autoupdate` | Turns off automatic updates | Everyone stays on the same version throughout the workshop |

A project folder can have its own `opencode.json`, which overrides these settings for that project. Keep that in mind if a participant's model suddenly changes inside one repo.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `opencode: command not found`, or "not recognized" on Windows | The terminal was opened before the install | Open a new terminal window. On Linux, `source ~/.bashrc` also works. |
| "is not set. Ask the facilitator for an updated script" | A placeholder wasn't filled in | Facilitator: fill in the endpoint and model at the top of the script. |
| 401 or "unauthorized" on the test prompt | Wrong, revoked or mistyped key | Run the script again and paste the key carefully. It's safe to run more than once. |
| 402 or "insufficient credits" | The key's credit limit is used up | Facilitator: raise the key's limit in OpenRouter. |
| 404 or "No endpoints found" | No provider serves the model at bf16/fp16 with no data collection, or all such providers are down | Check the model's providers on OpenRouter. Pick another model, or (facilitator's decision) add `fp8` to the precision setting. Also check the organization's privacy settings aren't stricter than intended. |
| 404 or "model not found" | Wrong model ID, or a base URL without `/api/v1` | Check both at the top of the script. The model ID is the one shown on the model's OpenRouter page. |
| Sessions keep the title "New session - \<date>" | The small model can't be reached, often because it has no bf16/fp16 provider | Leave the small-model placeholder so the main model handles titles, then run the script again. |
| Download fails, or the test prompt times out | Corporate proxy or firewall | Allow the hosts listed under *Before the workshop*. If you use a proxy, set `HTTPS_PROXY` before running the script. |
| Windows: "running scripts is disabled on this system" | The script was run without `-ExecutionPolicy Bypass` | Use the exact command in the Windows steps. |
| Windows: the script is blocked outright, or "Cannot invoke method" | Company policy (AppLocker or restricted language mode) | Ask IT to allow the script, or install inside WSL with the Linux script. |
| Windows: "Could not replace opencode.exe" | OpenCode is still running | Close all OpenCode windows and run the script again. |
| The wrong model or provider appears | Another OpenCode install or a project `opencode.json` takes priority | Run `which opencode` (Linux) or `where.exe opencode` (Windows) to find duplicates. Look for an `opencode.json` in the project folder. |
| Windows: slow, or odd terminal behaviour | Known limitations of native Windows | Use Windows Terminal, or run OpenCode inside WSL. |

OpenCode writes logs to `~/.local/share/opencode/log` on Linux and `%USERPROFILE%\.local\share\opencode\log` on Windows. Ask participants to share the newest log file when reporting a problem.

**To uninstall**, delete the `.opencode` folder and `.config/opencode` in the home folder, plus `.local/share/opencode` (saved sessions). On Linux, also remove the `# opencode` PATH lines the installer added to your shell profile (for example `~/.bashrc`). On Windows, also remove the `.opencode\bin` entry from your user PATH (Settings → System → About → Advanced system settings → Environment Variables).

## Appendix: the settings block

The full scripts are the two attached files, `setup-opencode.sh` and `setup-opencode.ps1`. Facilitators edit only the block at the top of each. The rest of each script checks these values, installs OpenCode and writes the settings described above.

### setup-opencode.sh (Linux and WSL)

```bash
# OpenRouter API base URL. The public endpoint is https://openrouter.ai/api/v1
OPENROUTER_BASE_URL="REPLACE_WITH_OPENROUTER_ENDPOINT_URL"

# OpenRouter API key. Leave the placeholder to make the script ask each
# participant for their own key (recommended), or paste a shared key here.
OPENROUTER_API_KEY="REPLACE_WITH_OPENROUTER_API_KEY"

# Main coding model: OpenRouter model ID exactly as shown on openrouter.ai,
# e.g. "vendor/model-name"
OPENCODE_MODEL="REPLACE_WITH_OPENROUTER_MODEL_ID"

# Small model for light background tasks such as naming sessions.
# Leave the placeholder to use the main model for these too.
OPENCODE_SMALL_MODEL="REPLACE_WITH_OPENROUTER_SMALL_MODEL_ID"

# Only route to OpenRouter providers serving the model at these precisions
# (comma-separated). Match what you will self-host later.
OPENROUTER_PRECISIONS="bf16,fp16"

# OpenCode version to install, e.g. "1.18.33". Empty = latest release.
# Pin a version so every participant runs the same build.
OPENCODE_VERSION=""
```

### setup-opencode.ps1 (Windows)

```powershell
# OpenRouter API base URL. The public endpoint is https://openrouter.ai/api/v1
$OpenRouterBaseUrl = "REPLACE_WITH_OPENROUTER_ENDPOINT_URL"

# OpenRouter API key. Leave the placeholder to make the script ask each
# participant for their own key (recommended), or paste a shared key here.
$OpenRouterApiKey = "REPLACE_WITH_OPENROUTER_API_KEY"

# Main coding model: OpenRouter model ID exactly as shown on openrouter.ai,
# e.g. "vendor/model-name"
$OpenCodeModel = "REPLACE_WITH_OPENROUTER_MODEL_ID"

# Small model for light background tasks such as naming sessions.
# Leave the placeholder to use the main model for these too.
$OpenCodeSmallModel = "REPLACE_WITH_OPENROUTER_SMALL_MODEL_ID"

# Only route to OpenRouter providers serving the model at these precisions
# (comma-separated). Match what you will self-host later.
$OpenRouterPrecisions = "bf16,fp16"

# OpenCode version to install, e.g. "1.18.33". Empty = latest release.
# Pin a version so every participant runs the same build.
$OpenCodeVersion = ""
```
