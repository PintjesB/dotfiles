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

    # Ensure fontconfig is installed
    if ! command -v fc-cache >/dev/null; then
        echo -e "${YELLOW}📦 Installing fontconfig...${NC}"
        sudo DEBIAN_FRONTEND=noninteractive apt install -y fontconfig
    fi

    # Create font directory if needed
    mkdir -p "$FONT_DIR"

    if [ ! -f "$FONT_DIR/${FONT}NerdFont-Regular.ttf" ]; then
        echo -e "${YELLOW}📦 Downloading ${FONT} Nerd Font...${NC}"
        
        # Install required tools
        if ! command -v unzip >/dev/null; then
            sudo DEBIAN_FRONTEND=noninteractive apt install -y unzip
        fi

        # Download and extract font
        curl -fLo "/tmp/${FONT}.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/${FONT}.zip"
        unzip -qo "/tmp/${FONT}.zip" -d "$FONT_DIR"
        rm -f "/tmp/${FONT}.zip"

        # Update font cache
        echo -e "${YELLOW}🔄 Updating font cache...${NC}"
        fc-cache -f -v "$FONT_DIR"
    fi

# Verify font installation
if ! fc-list | grep -i "Fira[ -]Code" >/dev/null; then
    echo -e "${RED}⛔ Font installation verification failed!${NC}"
    exit 1
fi

    echo -e "${GREEN}✅ Nerd Font installed successfully.${NC}"
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