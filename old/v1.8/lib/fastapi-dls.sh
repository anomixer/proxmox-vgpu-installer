#!/bin/bash
# lib/fastapi-dls.sh - FastAPI-DLS licensing server setup
# Part of proxmox-vgpu-installer v1.8
# Handles FastAPI-DLS Docker deployment and license token generation

# Detect primary IP address
detect_primary_ip() {
    local host_ip=""
    
    if command -v hostname >/dev/null 2>&1; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -z "$host_ip" ]; then
            host_ip=$(hostname -i 2>/dev/null | awk '{print $1}')
        fi
    fi
    
    if [ -z "$host_ip" ] && command -v ip >/dev/null 2>&1; then
        host_ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | head -n1)
        host_ip=${host_ip%%/*}
    fi
    
    echo "$host_ip"
}

# Install Docker and Docker Compose
install_docker() {
    log_info "Installing Docker-CE"
    
    run_command "Installing Docker-CE" "info" "apt remove -y docker.io docker-compose docker-compose-v2 podman-docker || true; \
        apt install ca-certificates curl -y; \
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
        chmod a+r /etc/apt/keyrings/docker.asc; \
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null; \
        apt update; \
        apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y"
}

# Pull FastAPI-DLS Docker image and generate certificates
prepare_fastapi_dls() {
    log_info "Preparing FastAPI-DLS"
    
    run_command "Docker pull FastAPI-DLS" "info" "docker pull collinwebdesigns/fastapi-dls:latest; \
        working_dir=/opt/docker/fastapi-dls/cert; \
        mkdir -p \$working_dir; \
        cd \$working_dir; \
        openssl genrsa -out \$working_dir/instance.private.pem 2048; \
        openssl rsa -in \$working_dir/instance.private.pem -outform PEM -pubout -out \$working_dir/instance.public.pem; \
        echo -e '\n\n\n\n\n\n\n' | openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout \$working_dir/webserver.key -out \$working_dir/webserver.crt; \
        docker volume create dls-db"
}

# Generate Docker Compose YAML file
generate_docker_compose() {
    local fastapi_dir="$1"
    local timezone="$2"
    local host_address="$3"
    local portnumber="$4"
    
    log_info "Generating Docker Compose YAML file"
    
    mkdir -p "$fastapi_dir"
    
    cat > "$fastapi_dir/docker-compose.yml" <<EOF
version: '3.9'

x-dls-variables: &dls-variables
  TZ: "$timezone"
  DLS_URL: "$host_address"
  DLS_PORT: "$portnumber"
  LEASE_EXPIRE_DAYS: 90  # 90 days is maximum
  DATABASE: sqlite:////app/database/db.sqlite
  DEBUG: "false"

services:
  wvthoog-fastapi-dls:
    image: collinwebdesigns/fastapi-dls:latest
    container_name: wvthoog-fastapi-dls
    restart: always
    working_dir: /app
    environment:
      <<: *dls-variables
      PYTHONPATH: /app
    ports:
      - "${portnumber}:443"
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    command: >
      uvicorn main:app
      --host 0.0.0.0 --port 443
      --ssl-keyfile /app/cert/webserver.key
      --ssl-certfile /app/cert/webserver.crt
      --loop asyncio
    volumes:
      - dls-db:/app/database
      - /opt/docker/fastapi-dls/cert:/app/cert
    healthcheck:
      test: ["CMD", "curl", "-k", "--fail", "https://127.0.0.1:443/-/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

volumes:
  dls-db:
EOF
    
    log_info "Docker Compose file created at $fastapi_dir/docker-compose.yml"
}

# Generate license scripts for Linux and Windows
generate_license_scripts() {
    local host_address="$1"
    local portnumber="$2"
    local licenses_dir="$3"
    
    log_info "Generating FastAPI-DLS license scripts"
    
    mkdir -p "$licenses_dir"
    
    # Create Linux script
    cat > "$licenses_dir/license_linux.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
DEST_DIR="/etc/nvidia/ClientConfigToken"
DEST="\${DEST_DIR}/client_configuration_token_\$(date +%Y%m%d_%H%M%S).tok"
mkdir -p "\$DEST_DIR"
curl -fsSLk "https://${host_address}:${portnumber}/-/client-token" -o "\$DEST"
if systemctl list-units --type=service 2>/dev/null | grep -qi nvidia-gridd; then
  systemctl restart nvidia-gridd
fi
nvidia-smi -q | grep -i license || true
echo "Token saved to: \$DEST"
EOF
    
    chmod +x "$licenses_dir/license_linux.sh"
    
    # Create Windows script
    cat > "$licenses_dir/license_windows.ps1" <<'EOF'
$ErrorActionPreference = "Stop"
$dest = "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_$(Get-Date -f 'yyyyMMdd_HHmmss').tok"

# Trust self-signed (process-local)
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint s, X509Certificate c, WebRequest r, int p) { return true; }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-WebRequest -Uri "https://__DLS_HOST__:__DLS_PORT__/-/client-token" -OutFile $dest -UseBasicParsing
Restart-Service NVDisplay.ContainerLocalSystem -Force -ErrorAction SilentlyContinue
& nvidia-smi -q | Select-String -SimpleMatch "License"
EOF
    
    # Inject host and port
    sed -i "s|__DLS_HOST__|$host_address|g; s|__DLS_PORT__|$portnumber|g" "$licenses_dir/license_windows.ps1"
    
    log_info "License scripts created in $licenses_dir"
    log_info "  - license_linux.sh (for Linux VMs)"
    log_info "  - license_windows.ps1 (for Windows VMs)"
}

# Setup FastAPI-DLS
setup_fastapi_dls() {
    log_info "Setting up FastAPI-DLS licensing server"
    echo ""
    
    # Check for FastAPI warning
    if [ "${FASTAPI_WARNING:-0}" = "1" ]; then
        log_warn "Detected host driver branch ${DRIVER_VERSION}. FastAPI-DLS requires gridd-unlock patches for vGPU 18.x and newer."
        log_warn "Review https://git.collinwebdesigns.de/vgpu/nvlts for licensing alternatives."
        echo ""
    fi
    
    # Prompt user
    local choice
    read -p "$(log_question "Do you want to license the vGPU? (y/n): ")" choice
    echo ""
    
    case "$choice" in
        y|Y)
            # Install Docker
            install_docker
            
            # Prepare FastAPI-DLS
            prepare_fastapi_dls
            
            # Get timezone
            local timezone="UTC"
            if command -v timedatectl >/dev/null 2>&1; then
                timezone=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone/ {print $2}' | awk '{print $1}')
            fi
            timezone=${timezone:-UTC}
            
            # Get host address
            local host_address
            host_address=$(detect_primary_ip)
            if [ -z "$host_address" ]; then
                host_address=$(hostname 2>/dev/null || echo "localhost")
            fi
            
            # Get port number
            echo ""
            local portnumber
            read -p "$(log_question "Enter the desired port number for FastAPI-DLS (default is 8443): ")" portnumber
            portnumber=${portnumber:-8443}
            log_warn "Don't use port 80 or 443 since Proxmox is using those ports"
            echo ""
            
            # Generate Docker Compose file
            local fastapi_dir=~/fastapi-dls
            generate_docker_compose "$fastapi_dir" "$timezone" "$host_address" "$portnumber"
            
            # Start Docker Compose
            run_command "Running Docker Compose" "info" "docker compose -f \"$fastapi_dir/docker-compose.yml\" up -d"
            
            # Generate license scripts
            generate_license_scripts "$host_address" "$portnumber" "$VGPU_DIR/licenses"
            
            # Display information
            echo ""
            log_debug "FastAPI-DLS health endpoint: https://$host_address:$portnumber/-/health"
            log_debug "Docker Compose defaults to the asyncio event loop for compatibility."
            log_debug "Review $fastapi_dir/docker-compose.yml if you need uvloop."
            echo ""
            log_warn "Copy license scripts from $VGPU_DIR/licenses to your VMs and execute them"
            echo ""
            
            return 0
            ;;
        n|N)
            log_warn "Skipping FastAPI-DLS deployment. You can run option 6 later if needed."
            echo ""
            return 0
            ;;
        *)
            log_error "Invalid choice. Please enter y or n."
            return 1
            ;;
    esac
}

# Remove FastAPI-DLS
remove_fastapi_dls() {
    log_info "Removing FastAPI-DLS"
    
    if command -v docker >/dev/null 2>&1; then
        run_command "Removing FastAPI-DLS" "notification" "docker rm -f -v wvthoog-fastapi-dls" || true
    else
        log_warn "Docker not found, skipping FastAPI-DLS removal"
    fi
}

# Check FastAPI-DLS health
check_fastapi_dls_health() {
    local host_address="${1:-localhost}"
    local portnumber="${2:-8443}"
    
    log_info "Checking FastAPI-DLS health..."
    
    if command -v curl >/dev/null 2>&1; then
        if curl -k --fail "https://$host_address:$portnumber/-/health" 2>/dev/null; then
            log_info "FastAPI-DLS is healthy"
            return 0
        else
            log_error "FastAPI-DLS health check failed"
            return 1
        fi
    else
        log_warn "curl not available, cannot check health"
        return 1
    fi
}

# Check if FastAPI-DLS is running
is_fastapi_dls_running() {
    if command -v docker >/dev/null 2>&1; then
        docker ps | grep -q "wvthoog-fastapi-dls"
    else
        return 1
    fi
}

# Get FastAPI-DLS status
get_fastapi_dls_status() {
    if is_fastapi_dls_running; then
        echo "FastAPI-DLS: Running"
        docker ps --filter "name=wvthoog-fastapi-dls" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "FastAPI-DLS: Not running"
    fi
}

# Module loaded indicator
module_init "fastapi-dls.sh"
