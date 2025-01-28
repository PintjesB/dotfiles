#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[1;31mError at line $LINENO\033[0m"' ERR

# Colors and formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize logging
exec > >(tee -i setup.log)
exec 2>&1

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
        # Install Homebrew if missing
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
        
        # Install Starship if not available
        if ! command -v starship >/dev/null; then
            echo -e "${YELLOW}🚀 Installing Starship...${NC}"
            sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- --yes --bin-dir "$HOME/.local/bin"
            export PATH="$HOME/.local/bin:$PATH"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
        fi
    fi
}

setup_shell() {
    echo -e "${BOLD}🐚 Configuring Zsh...${NC}"
    
    # Set default shell if not already Zsh
    if [[ "$SHELL" != *"zsh"* ]]; then
        echo -e "${YELLOW}🔀 Changing default shell to Zsh...${NC}"
        sudo chsh -s "$(command -v zsh)" "$USER"
    fi
    
    # Ensure Zsh is executed after configuration
    if [[ ! -f "$HOME/.zshrc" ]]; then
        touch "$HOME/.zshrc"
    fi
}

setup_chezmoi() {
    echo -e "${BOLD}🛠️ Setting up dotfiles with Chezmoi...${NC}"
    
    # Install Chezmoi if missing
    if ! command -v chezmoi >/dev/null; then
        echo -e "${YELLOW}📦 Installing Chezmoi...${NC}"
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" "v2.45.1"
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Apply dotfiles
    if [[ ! -d "$HOME/.local/share/chezmoi" ]]; then
        echo -e "${YELLOW}🚀 Initializing dotfiles...${NC}"
        chezmoi init --apply --verbose "https://github.com/PintjesB/dotfiles.git"
    else
        echo -e "${YELLOW}🔄 Updating existing dotfiles...${NC}"
        chezmoi update --verbose
    fi
}

finalize() {
    echo -e "\n${GREEN}✅ Setup complete!${NC}"
    echo -e "${BOLD}Restart your terminal or run:${NC}"
    echo -e "  ${YELLOW}exec zsh${NC}"
    echo -e "${BOLD}To verify everything:${NC}"
    echo -e "  ${YELLOW}chezmoi doctor${NC}"
}

# Main execution
echo -e "${BOLD}🖥️ Starting automated system setup...${NC}"
detect_platform
install_dependencies
setup_shell
setup_chezmoi
finalize