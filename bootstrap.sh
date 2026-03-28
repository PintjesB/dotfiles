#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[1;31mError at line $LINENO\033[0m"' ERR

# ─────────────────────────────────────────────
# Configuration (override via env vars)
# ─────────────────────────────────────────────
REPO_HTTPS="https://github.com/PintjesB/dotfiles.git"
LOG_SETUP="${LOG_SETUP:-true}"
INSTALL_NERDFONT="${INSTALL_NERDFONT:-true}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"

# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ "$LOG_SETUP" == "true" ]]; then
    exec > >(tee -i "$HOME/dotfiles-setup.log")
    exec 2>&1
fi

# ─────────────────────────────────────────────
detect_platform() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            source /etc/os-release
            case $ID in
                debian|ubuntu|pop) PLATFORM="debian" ;;
                fedora|rhel|centos) PLATFORM="fedora" ;;
                arch|manjaro) PLATFORM="arch" ;;
                *) echo -e "${RED}⛔ Unsupported Linux distro: $ID${NC}" >&2; exit 1 ;;
            esac
        else
            echo -e "${RED}⛔ Could not detect Linux distribution${NC}" >&2
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        PLATFORM="macos"
    else
        echo -e "${RED}⛔ Unsupported OS: $OSTYPE${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}✅ Detected platform: $PLATFORM${NC}"
}

# ─────────────────────────────────────────────
install_dependencies() {
    echo -e "${BOLD}📦 Installing system dependencies...${NC}"

    if [[ "$PLATFORM" == "macos" ]]; then
        if ! command -v brew >/dev/null; then
            echo -e "${YELLOW}🍺 Installing Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Add Homebrew to PATH for the rest of this script
            if [[ -f /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        fi
        brew install zsh git curl starship
        brew install zsh-syntax-highlighting zsh-autosuggestions
    else
        case $PLATFORM in
            debian)
                # Repair any interrupted dpkg state before touching apt
                if sudo dpkg --configure -a 2>&1 | grep -q "dpkg was interrupted"; then
                    echo -e "${RED}❌ Could not repair dpkg state automatically. Run 'sudo dpkg --configure -a' manually.${NC}" >&2
                    exit 1
                fi
                sudo dpkg --configure -a
                sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y  # fix broken deps
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    zsh git curl unzip fontconfig cron \
                    zsh-syntax-highlighting zsh-autosuggestions
                ;;
            fedora)
                sudo dnf install -y \
                    zsh git curl unzip fontconfig \
                    zsh-syntax-highlighting zsh-autosuggestions
                ;;
            arch)
                sudo pacman -Sy --noconfirm \
                    zsh git curl unzip fontconfig \
                    zsh-syntax-highlighting zsh-autosuggestions
                ;;
        esac

        if ! command -v starship >/dev/null; then
            echo -e "${YELLOW}🚀 Installing Starship...${NC}"
            mkdir -p ~/.local/bin
            sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- --yes --bin-dir ~/.local/bin
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi
}

# ─────────────────────────────────────────────
setup_shell() {
    echo -e "${BOLD}🐚 Configuring Zsh as default shell...${NC}"
    ZSH_PATH="$(command -v zsh)"

    if [[ "$SHELL" != "$ZSH_PATH" ]]; then
        echo -e "${YELLOW}🔀 Changing default shell to Zsh ($ZSH_PATH)...${NC}"
        # Add zsh to /etc/shells if not already there
        if ! grep -qF "$ZSH_PATH" /etc/shells; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells
        fi
        sudo chsh -s "$ZSH_PATH" "$USER"
        echo -e "${GREEN}✅ Default shell changed. Re-login to apply.${NC}"
    else
        echo -e "${GREEN}✅ Zsh is already the default shell.${NC}"
    fi
}

# ─────────────────────────────────────────────
setup_chezmoi() {
    echo -e "${BOLD}🛠️ Setting up dotfiles with Chezmoi...${NC}"

    if ! command -v chezmoi >/dev/null; then
        echo -e "${YELLOW}📦 Installing Chezmoi...${NC}"
        mkdir -p ~/.local/bin
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if [[ ! -d ~/.local/share/chezmoi/.git ]]; then
        echo -e "${YELLOW}🚀 Initializing dotfiles from repo...${NC}"
        chezmoi init --apply --verbose "$REPO_HTTPS"
    else
        echo -e "${YELLOW}🔄 Updating existing dotfiles...${NC}"
        chezmoi update --verbose
    fi
}

# ─────────────────────────────────────────────
setup_auto_update() {
    echo -e "${BOLD}⏰ Configuring automatic dotfile updates...${NC}"

    if [[ "$PLATFORM" == "macos" ]]; then
        _setup_launchd_agent
    else
        _setup_cronjob
    fi
}

_setup_cronjob() {
    local CRON_SCRIPT="$HOME/.local/bin/chezmoi-update.sh"
    local LOG_FILE="$HOME/.local/log/chezmoi-update.log"
    mkdir -p "$(dirname "$CRON_SCRIPT")" "$(dirname "$LOG_FILE")"

    echo -e "${YELLOW}📝 Writing cron script to $CRON_SCRIPT...${NC}"
    cat > "$CRON_SCRIPT" <<EOF
#!/bin/bash
# Ensure chezmoi is on PATH
export PATH="\$HOME/.local/bin:\$PATH"
LOG_FILE="$LOG_FILE"
mkdir -p "\$(dirname "\$LOG_FILE")"
{
    echo "=== Update started: \$(date) ==="
    "\$HOME/.local/bin/chezmoi" update --verbose
    echo "=== Update completed: \$(date) ==="
    echo ""
} >> "\$LOG_FILE" 2>&1
EOF
    chmod +x "$CRON_SCRIPT"

    # Validate cron schedule format
    if ! [[ "$CRON_SCHEDULE" =~ ^[0-9,*/-]+[[:space:]]+[0-9,*/-]+[[:space:]]+[0-9,*/-]+[[:space:]]+[0-9,*/-]+[[:space:]]+[0-9,*/-]+$ ]]; then
        echo -e "${RED}❌ Invalid CRON_SCHEDULE format: '$CRON_SCHEDULE'${NC}"
        return 1
    fi

    if ! crontab -l 2>/dev/null | grep -qF "$CRON_SCRIPT"; then
        echo -e "${YELLOW}➕ Adding cron job (schedule: $CRON_SCHEDULE)...${NC}"
        (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $CRON_SCRIPT") | crontab -
        echo -e "${GREEN}✅ Cron job added.${NC}"
    else
        echo -e "${GREEN}✅ Cron job already exists.${NC}"
    fi

    # Ensure cron daemon is running (absent on minimal Ubuntu cloud images)
    if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl is-enabled cron >/dev/null 2>&1; then
            echo -e "${YELLOW}⚙️ Enabling cron service...${NC}"
            sudo systemctl enable cron
        fi
        if ! systemctl is-active cron >/dev/null 2>&1; then
            echo -e "${YELLOW}▶️ Starting cron service...${NC}"
            sudo systemctl start cron
        fi
        echo -e "${GREEN}✅ Cron service is running.${NC}"
    fi
}

_setup_launchd_agent() {
    local PLIST="$HOME/Library/LaunchAgents/io.chezmoi.update.plist"
    mkdir -p "$(dirname "$PLIST")"
    local LOG_FILE="$HOME/.local/log/chezmoi-update.log"
    mkdir -p "$(dirname "$LOG_FILE")"

    echo -e "${YELLOW}📝 Writing launchd agent to $PLIST...${NC}"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.chezmoi.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.local/bin/chezmoi</string>
        <string>update</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF
    launchctl load "$PLIST" 2>/dev/null || launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    echo -e "${GREEN}✅ launchd agent installed.${NC}"
}

# ─────────────────────────────────────────────
install_nerdfont() {
    if [[ "$INSTALL_NERDFONT" != "true" ]]; then
        echo -e "${YELLOW}⏭️ Skipping Nerd Font install (INSTALL_NERDFONT=$INSTALL_NERDFONT).${NC}"
        return 0
    fi

    echo -e "${BOLD}🔠 Installing FiraCode Nerd Font...${NC}"
    local FONT="FiraCode"
    local FONT_DIR

    if [[ "$PLATFORM" == "macos" ]]; then
        FONT_DIR="$HOME/Library/Fonts"
    else
        FONT_DIR="$HOME/.local/share/fonts"
    fi
    mkdir -p "$FONT_DIR"

    if ls "$FONT_DIR/${FONT}"*NerdFont*.ttf &>/dev/null; then
        echo -e "${GREEN}✅ ${FONT} Nerd Font already installed.${NC}"
        return 0
    fi

    echo -e "${YELLOW}📦 Fetching latest Nerd Fonts release tag...${NC}"
    local LATEST_TAG
    LATEST_TAG=$(curl -fsI "https://github.com/ryanoasis/nerd-fonts/releases/latest" \
        | grep -i "^location:" | sed 's|.*/||' | tr -d '[:space:]')
    LATEST_TAG="${LATEST_TAG:-v3.3.0}"  # fallback
    echo -e "${YELLOW}   Using version: $LATEST_TAG${NC}"

    curl -fLo "/tmp/${FONT}.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST_TAG}/${FONT}.zip"
    unzip -qo "/tmp/${FONT}.zip" -d "$FONT_DIR"
    rm -f "/tmp/${FONT}.zip"

    if [[ "$PLATFORM" != "macos" ]]; then
        fc-cache -f "$FONT_DIR"
    fi

    echo -e "${GREEN}✅ ${FONT} Nerd Font installed. Set it in your terminal emulator.${NC}"
}

# ─────────────────────────────────────────────
finalize() {
    echo -e "\n${GREEN}${BOLD}✅ Setup complete!${NC}"
    echo -e "${BOLD}Restart your terminal or run:${NC}"
    echo -e "  ${YELLOW}exec zsh${NC}"
    echo -e "\n${BOLD}Auto-update details:${NC}"
    if [[ "$PLATFORM" == "macos" ]]; then
        echo -e "  ${YELLOW}Method:${NC}    launchd (runs daily at 03:00)"
        echo -e "  ${YELLOW}Log:${NC}       ~/.local/log/chezmoi-update.log"
        echo -e "  ${YELLOW}Agent:${NC}     ~/Library/LaunchAgents/io.chezmoi.update.plist"
    else
        echo -e "  ${YELLOW}Method:${NC}    cron (schedule: $CRON_SCHEDULE)"
        echo -e "  ${YELLOW}Log:${NC}       ~/.local/log/chezmoi-update.log"
        echo -e "  ${YELLOW}View jobs:${NC} crontab -l"
    fi
    echo -e "\n${BOLD}Setup log:${NC} ~/dotfiles-setup.log"
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
echo -e "${BOLD}🖥️ Starting automated dotfiles setup...${NC}"
detect_platform
install_dependencies
install_nerdfont
setup_shell
setup_chezmoi
setup_auto_update
finalize
