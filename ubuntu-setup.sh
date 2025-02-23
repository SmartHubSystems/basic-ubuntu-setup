#!/bin/bash

# Set up logging
LOG_FILE="/var/log/server-setup.log"
exec 1> >(tee -a "$LOG_FILE") 2>&1

echo "Starting server setup at $(date)"

# Function to handle errors
handle_error() {
    echo "Error occurred in line $1"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Function to check if a command was successful
check_success() {
    if [ $? -eq 0 ]; then
        echo "✓ $1 completed successfully"
    else
        echo "✗ Error: $1 failed"
        exit 1
    fi
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (with sudo)"
    exit 1
fi

# Create a non-root user if SETUP_USER is provided
if [ ! -z "$SETUP_USER" ]; then
    echo "Creating non-root user: $SETUP_USER"
    useradd -m -s /bin/bash "$SETUP_USER"
    usermod -aG sudo "$SETUP_USER"
    # Generate a random password and store it in the log file
    TEMP_PASSWORD=$(openssl rand -base64 12)
    echo "$SETUP_USER:$TEMP_PASSWORD" | chpasswd
    echo "Created user $SETUP_USER with temporary password: $TEMP_PASSWORD"
    echo "Please change this password immediately after login"
fi

echo "Updating system packages..."
apt update
apt upgrade -y
check_success "System update"

echo "Installing git..."
apt install -y git
check_success "Git installation"

echo "Installing vim..."
apt install -y vim
check_success "Vim installation"

echo "Setting up Vim configuration..."
# Function to setup vim for a user
setup_vim_for_user() {
    local USER_HOME="/home/$1"
    if [ "$1" = "root" ]; then
        USER_HOME="/root"
    fi
    
    if [ -d "$USER_HOME/.vim_runtime" ]; then
        echo "Removing existing .vim_runtime directory for $1..."
        rm -rf "$USER_HOME/.vim_runtime"
    fi
    
    git clone --depth=1 https://github.com/amix/vimrc.git "$USER_HOME/.vim_runtime"
    sh "$USER_HOME/.vim_runtime/install_awesome_vimrc.sh"
    chown -R "$1:$1" "$USER_HOME/.vim_runtime"
}

# Setup vim for root
setup_vim_for_user "root"
# Setup vim for SETUP_USER if provided
if [ ! -z "$SETUP_USER" ]; then
    setup_vim_for_user "$SETUP_USER"
fi
check_success "Vim configuration"

echo "Installing Docker..."
# Check if Docker is already installed
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    check_success "Docker installation"
else
    echo "Docker is already installed"
fi

echo "Installing Docker Compose..."
apt install -y docker-compose-plugin
check_success "Docker Compose installation"

# Add user to docker group
if [ ! -z "$SETUP_USER" ]; then
    usermod -aG docker "$SETUP_USER"
    check_success "Adding user to docker group"
fi

echo "Installing Python and related tools..."
apt install -y python3 python3-pip python3-venv
check_success "Python installation"

# Install uv using curl
curl -LsSf https://raw.githubusercontent.com/astral-sh/uv/main/install.sh | sh
check_success "uv installation"

# If we have a non-root user, set up Python environment for them
if [ ! -z "$SETUP_USER" ]; then
    # Create a Python virtual environment
    sudo -u "$SETUP_USER" mkdir -p "/home/$SETUP_USER/python_envs"
    sudo -u "$SETUP_USER" python3 -m venv "/home/$SETUP_USER/python_envs/default"
    
    # Add Python environment activation to .bashrc
    echo "# Python virtual environment" >> "/home/$SETUP_USER/.bashrc"
    echo "source ~/python_envs/default/bin/activate" >> "/home/$SETUP_USER/.bashrc"
fi

echo "Setup completed successfully at $(date)"
echo "Please log out and log back in for group changes to take effect"

if [ ! -z "$SETUP_USER" ]; then
    echo "Important: Please change the password for $SETUP_USER immediately using:"
    echo "sudo passwd $SETUP_USER"
fi
