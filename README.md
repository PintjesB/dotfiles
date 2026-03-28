# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## What's included

| File | Description |
|------|-------------|
| `dot_zshrc` | Zsh config — history, completion, plugins, aliases, Starship |
| `dot_config/starship.toml` | Starship prompt theme |
| `bootstrap.sh` | One-shot setup script for new machines |

**Installed by bootstrap:**
- Zsh + zsh-syntax-highlighting + zsh-autosuggestions
- [Starship](https://starship.rs/) prompt
- [FiraCode Nerd Font](https://www.nerdfonts.com/font-downloads)
- chezmoi (dotfile manager)
- Auto-update job (cron on Linux, launchd on macOS)

---

## Setting up a new machine

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/PintjesB/dotfiles/refs/heads/master/bootstrap.sh | bash
```

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/PintjesB/dotfiles/refs/heads/master/bootstrap.sh | bash
```

> **Note:** On macOS, make sure Xcode Command Line Tools are installed first:
> ```bash
> xcode-select --install
> ```

### Options

You can override these env vars before running the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTALL_NERDFONT` | `true` | Install FiraCode Nerd Font |
| `LOG_SETUP` | `true` | Write setup log to `~/dotfiles-setup.log` |
| `CRON_SCHEDULE` | `0 3 * * *` | Auto-update schedule (Linux cron only) |

Example:
```bash
INSTALL_NERDFONT=false curl -fsSL ... | bash
```

---

## Keeping dotfiles up-to-date

### Apply changes from the repo

```bash
chezmoi update
```

### Save local changes back to the repo

```bash
chezmoi cd
chezmoi re-add
git add -A
git commit -m "chore: update dotfiles"
git push
```

### One-liner

```bash
chezmoi cd && chezmoi re-add && git add -A && git commit -m "chore: update" && git push
```

---

## Auto-update

The bootstrap script installs a background job that runs `chezmoi update` daily at 03:00.

- **Linux:** cron job — view with `crontab -l`
- **macOS:** launchd agent — at `~/Library/LaunchAgents/io.chezmoi.update.plist`
- **Log:** `~/.local/log/chezmoi-update.log`
