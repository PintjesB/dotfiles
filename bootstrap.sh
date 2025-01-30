#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[1;31mError at line $LINENO\033[0m"' ERR

# Configuration
REPO_HTTPS="https://github.com/PintjesB/dotfiles.git"
LOG_SETUP="${LOG_SETUP:-true}"  # Set to 'false' to disable logging
INSTALL_NERDFONT="${INSTALL_NERDFONT:-true}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"  # Default: daily at 3 AM

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

setup_cronjob() {
    echo -e "${BOLD}⏰ Configuring automatic updates...${NC}"
    
    # Ensure CRON_SCHEDULE is set
    if [ -z "$CRON_SCHEDULE" ]; then
        echo -e "${RED}❌ CRON_SCHEDULE is not set! Exiting.${NC}"
        return 1
    fi
    
    # Define script path
    local CRON_SCRIPT="$HOME/.local/bin/chezmoi-cron.sh"
    echo -e "${YELLOW}📝 Creating cron script at $CRON_SCRIPT${NC}"
    
    # Create cron script
    cat > "$CRON_SCRIPT" <<- 'EOL'
	#!/bin/bash
	CHEZMOI_BIN="$HOME/.local/bin/chezmoi"
	LOG_FILE="/var/log/chezmoi_cron.log"
	
	{
	    echo "=== Update started: $(date) ==="
	    "$CHEZMOI_BIN" update --verbose
	    echo "=== Update completed: $(date) ==="
	    echo ""
	} >> "$LOG_FILE" 2>&1
	EOL

    chmod +x "$CRON_SCRIPT"
    
    # Ensure user has a crontab before modifying it
    echo -e "${YELLOW}⏲️ Adding cron job (schedule: $CRON_SCHEDULE)${NC}"

    # Debug: Print current crontab
    echo "CRON_SCHEDULE: $CRON_SCHEDULE"
    echo "CRON_SCRIPT: $CRON_SCRIPT"


    echo "🔍 Current crontab entries before modification:"
    crontab -l 2>/dev/null || echo "(No existing crontab found)"

    # Check if the cron job already exists
    if ! (crontab -l 2>/dev/null | grep -q "$CRON_SCRIPT"); then
        echo "🚨 No existing cron job found for $CRON_SCRIPT"
        
        # Add cron job
        (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $CRON_SCRIPT") | crontab -
        
        # Verify if it was actually added
        echo "🔍 Checking crontab contents after adding..."
        crontab -l
    else
        echo "✅ Cron job already exists!"
    fi
}

install_nerdfont() {
    echo -e "${BOLD}🔠 Installing Nerd Font...${NC}"
    local FONT="FiraCode"
    local FONT_DIR="$HOME/.local/share/fonts"

    if ! command -v fc-cache >/dev/null; then
        echo -e "${YELLOW}📦 Installing fontconfig...${NC}"
        sudo DEBIAN_FRONTEND=noninteractive apt install -y fontconfig
    fi

    mkdir -p "$FONT_DIR"

    if [ ! -f "$FONT_DIR/${FONT}NerdFont-Regular.ttf" ]; then
        echo -e "${YELLOW}📦 Downloading ${FONT} Nerd Font...${NC}"
        
        if ! command -v unzip >/dev/null; then
            sudo DEBIAN_FRONTEND=noninteractive apt install -y unzip
        fi

        curl -fLo "/tmp/${FONT}.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/${FONT}.zip"
        unzip -qo "/tmp/${FONT}.zip" -d "$FONT_DIR"
        rm -f "/tmp/${FONT}.zip"

        echo -e "${YELLOW}🔄 Updating font cache...${NC}"
        fc-cache -f -v "$FONT_DIR"
    fi

    echo -e "${YELLOW}⚠️  Skipping font verification - ensure terminal is configured to use Nerd Fonts${NC}"
    echo -e "${GREEN}✅ Font installation attempted. Manual verification recommended.${NC}"
}

finalize() {
    echo -e "\n${GREEN}✅ Setup complete!${NC}"
    echo -e "${BOLD}Restart your terminal or run:${NC}"
    echo -e "  ${YELLOW}exec zsh${NC}"
    echo -e "\n${BOLD}Cron job details:${NC}"
    echo -e "  ${YELLOW}Schedule:${NC} $CRON_SCHEDULE"
    echo -e "  ${YELLOW}Log file:${NC} ~/.chezmoi_cron.log"
    echo -e "  ${YELLOW}View cron jobs:${NC} crontab -l"
}

# Main execution
echo -e "${BOLD}🖥️ Starting automated dotfiles setup...${NC}"
detect_platform
install_dependencies
install_nerdfont
setup_shell
setup_chezmoi
setup_cronjob
finalize