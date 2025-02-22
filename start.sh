#!/bin/bash

if [ -f end ]; then
    echo "Renaming 'end' file to '.env'..."
    mv end .env
else
    echo "File 'end' not found. Continue..."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
else
    echo "Cannot detect OS. Exiting."
    exit 1
fi

install_docker_debian() {
    echo "Installing Docker on Debian/Ubuntu..."
    sudo apt update -y
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl enable --now docker
}

install_docker_arch() {
    echo "Installing Docker on Arch Linux..."
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm docker
    sudo systemctl enable --now docker
}

install_docker_fedora() {
    echo "Installing Docker on Fedora..."
    sudo dnf update -y
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm -f get-docker.sh
    sudo systemctl enable --now docker
}

if ! command -v docker &> /dev/null; then
    case "$OS_ID" in
        ubuntu|debian)
            install_docker_debian
            ;;
        arch)
            install_docker_arch
            ;;
        fedora)
            install_docker_fedora
            ;;
        *)
            echo "Unsupported OS: $OS_ID"
            exit 1
            ;;
    esac
else
    echo "Docker is already installed."
fi

if ! docker ps -a --filter "name=mariadb" --format '{{.Names}}' | grep -w mariadb &> /dev/null; then
    echo "MariaDB container not found. Creating container..."
    if [ -f .env ]; then
        export $(grep -v '^#' .env | xargs)
    else
        echo ".env file not found! Exiting."
        exit 1
    fi
    docker run -d --restart always --name mariadb \
        -v ~/docker/mariadb:/var/lib/mysql:Z \
        -p $MARIADB_PORT:$MARIADB_PORT \
        -e MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD \
        -e MARIADB_DATABASE=$MARIADB_DATABASE \
        -e MARIADB_USER=$MARIADB_USER \
        -e MARIADB_PASSWORD=$MARIADB_USER_PASSWORD \
        mariadb:latest
else
    echo "MariaDB container already exists."
fi

if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" || "$OS_ID" == "arch" ]]; then
    if ! command -v ufw &> /dev/null; then
        echo "ufw not found. Installing ufw..."
        case "$OS_ID" in
            ubuntu|debian)
                sudo apt install -y ufw
                ;;
            arch)
                sudo pacman -S --noconfirm ufw
                ;;
        esac
    else
        echo "ufw is already installed."
    fi
    echo "Allowing port $MARIADB_PORT through ufw..."
    sudo ufw allow $MARIADB_PORT/tcp
    sudo ufw reload
elif [ "$OS_ID" == "fedora" ]; then
    if ! systemctl is-active --quiet firewalld; then
        echo "Firewalld is not active. Installing and starting firewalld..."
        sudo dnf install -y firewalld
        sudo systemctl enable --now firewalld
    else
        echo "Firewalld is already active."
    fi
    echo "Opening port $MARIADB_PORT in firewalld..."
    sudo firewall-cmd --permanent --add-port=$MARIADB_PORT/tcp
    sudo firewall-cmd --reload
fi

echo "Setup complete."
    
