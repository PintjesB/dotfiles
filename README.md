# chezmoi
## Setting up a new machine
### Linux
```bash
curl -fsSL https://raw.githubusercontent.com/PintjesB/dotfiles/refs/heads/master/bootstrap.sh | bash
```
### MacOS
```ZSH

```
## Keeping chezmoi up-to-date
```bash
chezmoi cd && chezmoi re-add && git add FILE && git commit -m "MESSAGE" && git push
```
