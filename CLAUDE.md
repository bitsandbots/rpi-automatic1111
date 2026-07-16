# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A self-contained Bash installer (`setup_sd.sh`, ~10,000 lines) that installs AUTOMATIC1111 Stable Diffusion WebUI on Raspberry Pi 5-class ARM64 hardware (Raspberry Pi 5, Raspberry Pi 500, Compute Module 5), CPU-only. There is no application source code here — the "product" is the installer script itself, which in turn generates a runtime launcher script and an optional Tkinter GUI at install time. Remote installs run via:

```bash
curl -sSL https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

## Repo layout

- `setup_sd.sh` — the entire installer (~9800 lines, single file). This is what you'll almost always be editing.
- `validate_bundle.sh` — static validation script, run before publishing changes to `setup_sd.sh`.
- `sd_gui_banner.png` / `sd_icon.png` — artwork copied into the install (banner into the GUI app, icon into `~/.local/share/icons/...`). The icon is also embedded as base64 directly inside `setup_sd.sh` (search `SD_ICON_PNG_B64`) as a fallback if the standalone PNG isn't present alongside the script (e.g. for the piped-curl remote install).
- `README.md` — user-facing install/usage docs; treat as the source of truth for installer *behavior* (menu options, file paths created, uninstall behavior) when making changes.

## Commands

There is no build/test/lint toolchain (no package.json, no CI config). Validation is entirely the one script:

```bash
./validate_bundle.sh
```

Run this after any edit to `setup_sd.sh`, before publishing. It checks:
- `setup_sd.sh` exists and is executable, and passes `bash -n` syntax check
- the embedded GUI Python (extracted from the `.sd_gui_app.py` heredoc) passes `python3 -m py_compile`
- the venv is created directly at its final path (`$VENV_DIR`) with no staged venv path (`STAGE_VENV_DIR` must NOT exist)
- model SHA-256 verification logic (`sha256sum "$temporary"`, `expected_hash`, "SHA-256 verification failed") is present
- runtime PID files are installation-scoped under `$INSTALL_ROOT/.sd-runtime`, and no shared `/tmp/sd_webui.pid` / `/tmp/sd_gui.pid` paths have been reintroduced
- the pinned WebUI commit check (`git rev-parse HEAD`) and OpenAI CLIP import check (`import clip`) are present

When editing `setup_sd.sh`, keep these invariants intact — `validate_bundle.sh` greps for specific literal strings/variable names, so renaming these without updating the validator will fail it.

To manually syntax-check just the script: `bash -n setup_sd.sh`.

There is no sandboxed way to actually run the installer outside of real (or closely emulated) Raspberry Pi 5-class ARM64 hardware — `validate_platform()` hard-fails on architecture (`uname -m` must be `aarch64`), device-tree model string, and OS id. Don't attempt a full end-to-end run in a generic dev container; rely on static checks (`bash -n`, `validate_bundle.sh`, careful reading) plus targeted manual testing on real hardware.

## Architecture of `setup_sd.sh`

The script runs in **two stages that are easy to conflate** — installer-time code executes immediately when the script runs, but a large portion of the script is heredoc content that is only *written to disk* at install time and executed later, as a separate program. Keep clear which stage you're editing:

1. **Installer logic** (runs once, live, during install). This is NOT a single contiguous block — live logic (menu, validation, staged clone/swap, venv/pip setup, GUI/desktop-file wiring, final JSON metadata) is interleaved with the generated-artifact heredocs described below, and a large middle portion of the file (roughly lines 2200–9550) is base64-encoded image data (the embedded icon fallback and GUI banner), not logic. Don't assume a clean top/bottom split by line number — grep for the function/heredoc names below instead.
   - Interactive menu (`show_installer_menu`, `show_menu`/menu loop) toggles: download bundled models, install GUI launcher, create desktop shortcut, create menu launcher, install location. The "Install files location" prompt validates the entered path against an absolute-path, safe-character allowlist (`^/[A-Za-z0-9._/-]*$`) before accepting it — this value is later baked verbatim into generated heredoc scripts (see below), so it must never be allowed to contain `"`, `` ` ``, `$`, or `\`.
   - `validate_platform()` (line ~190) — hard gate on arch/hardware model/OS/disk/RAM before touching anything. A `check_connectivity()` check (curl against huggingface.co/github.com, falling back to `ping`) runs right after and hard-fails the install if there's no network.
   - `install_sd_launcher_icon()` (line ~463) is defined once, unconditionally, right after the `run_sd.sh` heredoc closes — it's shared by both the `INCLUDE_GUI=1` desktop-integration branch and the `INCLUDE_GUI!=1` CLI-only-launcher branch further down, so it must stay defined outside both `if` blocks rather than nested inside either one (it used to live only inside the `INCLUDE_GUI=1` block, which made the CLI-only branch's call to it fail with "command not found" — currently unreachable given the menu coupling, but would break immediately if that coupling is ever relaxed).
   - Per-run install logging: `_log_init`/`progress`/`ok`/`fail` write timestamped lines to `$INSTALL_ROOT/.sd-install-<timestamp>.log` in addition to their colored stdout output — keep new status messages going through these helpers rather than raw `echo` so they land in the log.
   - Staged install with rollback: clones WebUI into `$STAGE_WEBUI_DIR` (a `.sd-install-$$`-tagged dir), only swaps it into place at `$WEBUI_DIR` after everything (deps, models) succeeds. Prior install is moved to `$BACKUP_WEBUI_DIR`/`$BACKUP_VENV_DIR` and restored by `rollback_install()` (a `trap ... ERR INT TERM`) if anything fails after the swap begins (`SWAP_STARTED=1`). Read `rollback_install`/`SWAP_STARTED` before changing the swap sequence — it's the safety net for a failed reinstall.
   - Pinned WebUI commit: `82a973c04367123ae98bd9abdf80d9eda9b910e2`, verified via `git rev-parse HEAD` after checkout. Two source patches are applied post-checkout: pointing the Stability-AI stablediffusion submodule at a CI mirror, and adding `--no-build-isolation --no-use-pep517` to CLIP's pip install.
   - Model downloads (`download_if_missing`) verify SHA-256 against Hugging Face's `x-linked-etag` header before activating the file — never disable/weaken this check silently. A separate post-download pass (`_verify_model`) re-checks each staged model file is present and non-empty before the swap.
   - Virtualenv is created **directly at its final path** (`$VENV_DIR`), not staged and moved — this avoids broken absolute paths inside the venv (see `validate_bundle.sh`'s explicit check against a `STAGE_VENV_DIR`). Pip installs pin versions (`pip<24.1`, `setuptools<70`, `pytorch-lightning==1.9.5`, a pinned CLIP commit) and use CPU-only PyTorch (`--index-url https://download.pytorch.org/whl/cpu`). CLIP import is verified with a `python - <<'PYVERIFY'` check immediately after install.
   - GUI installation embeds a full Tkinter app plus icon/desktop-file wiring (see below).
   - After the swap completes, the installer writes `$INSTALL_ROOT/.sd-install-info.json` (hardware/OS/kernel, resolved paths, WebUI commit, python version, which menu toggles were chosen) and then runs a `$VENV_DIR/bin/python` snippet that imports `torch`/`clip` and lists discovered checkpoints, writing results to `$INSTALL_ROOT/.sd-verify-result.json`. This final verification is diagnostic only (`set +e` around it, non-zero exit is reported but doesn't fail the install) — don't make it fatal without deliberately deciding to change that behavior.

2. **Generated artifacts** (written via heredocs, executed at *runtime*, not install time):
   - `$INSTALL_ROOT/run_sd.sh` (heredoc `cat > "$RUN_SD_PATH" <<RUNEOF ... RUNEOF`, ~lines 371–458): the persistent CLI launcher. Menu options: LAN mode (`--listen`, first run installs deps), Offline mode (`--skip-install`), Stop running (kills the tracked PID only after verifying `/proc/$PID/cwd` and cmdline match *both before the initial `TERM` and again immediately before the final `KILL`* — the re-check before `KILL` matters because the grace-period loop only polls `kill -0` (PID existence), which can't detect the PID being recycled by an unrelated process mid-wait), Uninstall (removes webui dir, venv, GUI files, desktop/menu entries, runtime dir, and itself). All PID files live under `$INSTALL_ROOT/.sd-runtime` (`webui.pid`, `gui.pid`), never in shared `/tmp` paths.
   - `$INSTALL_ROOT/.sd_gui_app.py` (heredoc `cat <<'EOF' > .../.sd_gui_app.py`, ~lines 9556–9786): a Tkinter GUI wrapping the same four actions (LAN/Offline/Stop/Uninstall) plus "Open WebUI". Placeholder tokens like `"__RUN_SD_PATH__"`, `"__WEBUI_DIR__"`, `"__BANNER_PATH__"`, `"__GUI_PID_FILE__"` inside this heredoc are substituted by a separate `python3 - ... <<'PY_PATCH'` step right after the heredoc closes (~lines 9788–9798) — if you add new install-time values the GUI needs, add both the placeholder in the heredoc *and* a corresponding `.replace(...)` in `PY_PATCH`. This `PY_PATCH` step substitutes via Python's `repr()`, which is the correct way to safely embed an installer-time value into generated code — the `run_sd.sh`/`.sd_gui_runner.sh` heredocs above do NOT have an equivalent escaping step, which is exactly why the install-path allowlist mentioned above is the load-bearing safeguard for those.
   - `$INSTALL_ROOT/.sd_gui_runner.sh` — trivial wrapper that just execs the GUI app with `python3`.
   - Desktop integration: `.desktop` files for the app menu (`~/.local/share/applications/sd-gui.desktop`) and desktop shortcut (`~/Desktop/StableDiffusionGUI.desktop`), plus a `quick_exec=1` patch into `pcmanfm`/`libfm` configs so double-clicking the desktop shortcut runs it without a confirmation prompt.

Note: line numbers above drift as the script is edited — treat them as approximate anchors (grep for the quoted markers, e.g. `cat > "\$RUN_SD_PATH"`) rather than exact.

Because heredocs use a mix of quoted (`<<'EOF'`, no expansion) and unquoted (`<<RUNEOF`, `<<EOF`) delimiters, variable interpolation is deliberate and easy to break: `\$var` inside an unquoted-delimiter heredoc defers expansion to when the *generated* script runs, while `$var` bakes the installer's current value in at generation time. When touching any heredoc, check the delimiter's quoting before changing `$` escaping.

## Editing conventions specific to this script

- Anything user-facing (menu text, uninstall confirmation, file paths created) should stay in sync with `README.md`.
- Prefer installation-scoped paths (`$INSTALL_ROOT/...`, `$RUNTIME_DIR`) over shared global paths (`/tmp/...`) — this lets multiple installs coexist and is load-bearing for the "custom install location" menu option.
- Don't loosen `set -euo pipefail` (present at the top of both the installer and the generated `run_sd.sh`) or add broad `|| true` swallowing around steps that are supposed to be fatal (platform validation, commit verification, hash verification).
- If you change how the venv is created/moved or how PID files are named, update `validate_bundle.sh`'s corresponding grep checks in the same change — they're the only regression protection here.
