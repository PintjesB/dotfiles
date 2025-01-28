#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[1;31mError at line $LINENO\033[0m"' ERR

# Configuration
REPO_HTTPS="https://github.com/PintjesB/dotfiles.git"
LOG_SETUP="${LOG_SETUP:-true}"  # Set to 'false' to disable logging
INSTALL_NERDFONT="${INSTALL_NERDFONT:-true}"

# Colors and formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize logging
if [[ "$LOG_SETUP" == "true" ]]; then
    exec > >(tee -i setup.log)
    exec 2>&1
fi

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
}

install_dependencies() {
    echo -e "${BOLD}📦 Installing system dependencies...${NC}"
    
    if [[ "$PLATFORM" == "macos" ]]; then
        if ! command -v brew >/dev/null; then
            echo -e "${YELLOW}🍺 Installing Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        brew install zsh git curl starship
        brew install zsh-syntax-highlighting zsh-autosuggestions
    else
        case $PLATFORM in
            debian)
                sudo DEBIAN_FRONTEND=noninteractive apt update -y
                sudo DEBIAN_FRONTEND=noninteractive apt install -y zsh git curl \
                    zsh-syntax-highlighting zsh-autosuggestions
                ;;
            fedora)
                sudo dnf install -y zsh git curl \
                    zsh-syntax-highlighting zsh-autosuggestions
                ;;
            arch)
                sudo pacman -Sy --noconfirm zsh git curl \
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

setup_shell() {
    echo -e "${BOLD}🐚 Configuring Zsh...${NC}"
    
    if [[ "$SHELL" != *"zsh"* ]]; then
        echo -e "${YELLOW}🔀 Changing default shell to Zsh...${NC}"
        sudo chsh -s "$(command -v zsh)" "$USER"
    fi
}

setup_chezmoi() {
    echo -e "${BOLD}🛠️ Setting up dotfiles with Chezmoi...${NC}"
    
    if ! command -v chezmoi >/dev/null; then
        echo -e "${YELLOW}📦 Installing Chezmoi...${NC}"
        mkdir -p ~/.local/bin
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    if [[ ! -d ~/.local/share/chezmoi ]]; then
        echo -e "${YELLOW}🚀 Initializing dotfiles...${NC}"
        chezmoi init --apply --verbose "$REPO_HTTPS"
    else
        echo -e "${YELLOW}🔄 Updating existing dotfiles...${NC}"
        chezmoi update --verbose
    fi
}

install_nerdfont() {
    echo -e "${BOLD}🔠 Installing Nerd Font...${NC}"
    local FONT="FiraCode"
    local FONT_DIR="$HOME/.local/share/fonts"
    local NERD_FONT_NAME="FiraCode Nerd Font Mono"

    # Install font
    if [ ! -f "$FONT_DIR/${FONT}NerdFont-Regular.ttf" ]; then
        echo -e "${YELLOW}📦 Downloading ${FONT} Nerd Font...${NC}"
        mkdir -p "$FONT_DIR"
        
        if ! command -v unzip >/dev/null; then
            sudo DEBIAN_FRONTEND=noninteractive apt install -y unzip
        fi

        curl -fLo "/tmp/${FONT}.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/${FONT}.zip"
        unzip -qo "/tmp/${FONT}.zip" -d "$FONT_DIR"
        rm -f "/tmp/${FONT}.zip"
        fc-cache -f "$FONT_DIR"
    fi

    # Auto-configure terminals
    echo -e "${YELLOW}🖥️ Attempting terminal font configuration...${NC}"
    
    # 1. Attempt to detect and configure GNOME Terminal (common in Ubuntu)
    if command -v gsettings &>/dev/null && [ -d /usr/share/gnome-terminal ]; then
        echo -e "${YELLOW}  → Configuring GNOME Terminal...${NC}"
        local PROFILE_PATH="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')"
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE_PATH}/" \
            font "${NERD_FONT_NAME} 12"
    fi

    # 2. Configure common config-based terminals
    configure_terminal_config() {
        # Alacritty
        if [ -f "$HOME/.config/alacritty/alacritty.yml" ]; then
            echo -e "${YELLOW}  → Configuring Alacritty...${NC}"
            if ! grep -q "family: ${NERD_FONT_NAME}" "$HOME/.config/alacritty/alacritty.yml"; then
                cp "$HOME/.config/alacritty/alacritty.yml" "$HOME/.config/alacritty/alacritty.yml.bak"
                printf "\nfont:\n  normal:\n    family: %s\n    style: Regular\n" "$NERD_FONT_NAME" \
                    >> "$HOME/.config/alacritty/alacritty.yml"
            fi
        fi

        # Kitty
        if [ -f "$HOME/.config/kitty/kitty.conf" ]; then
            echo -e "${YELLOW}  → Configuring Kitty...${NC}"
            if ! grep -q "font_family ${NERD_FONT_NAME}" "$HOME/.config/kitty/kitty.conf"; then
                echo "font_family ${NERD_FONT_NAME}" >> "$HOME/.config/kitty/kitty.conf"
            fi
        fi
    }

    # 3. Configure Linux console (requires root)
    if [ -d /usr/share/consolefonts ] && [ $(id -u) -eq 0 ]; then
        echo -e "${YELLOW}  → Configuring console fonts...${NC}"
        cp "${FONT_DIR}/${FONT}NerdFont-Regular.ttf" /usr/share/consolefonts/
        setupcon --save-only --force
    fi

    echo -e "${GREEN}✅ Font configuration attempted. Changes may require terminal restart.${NC}"
}

finalize() {
    echo -e "\n${GREEN}✅ Setup complete!${NC}"
    echo -e "${BOLD}Restart your terminal or run:${NC}"
    echo -e "  ${YELLOW}exec zsh${NC}"
}

# Main execution
echo -e "${BOLD}🖥️ Starting automated dotfiles setup...${NC}"
detect_platform
install_dependencies
install_nerdfont
setup_shell
setup_chezmoi
finalize