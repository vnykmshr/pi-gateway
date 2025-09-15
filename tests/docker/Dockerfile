# Pi Gateway Docker Test Environment
# ARM64 container for cross-platform Pi Gateway testing

FROM arm64v8/debian:bookworm-slim

# Install basic system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    sudo \
    systemd \
    openssh-server \
    systemctl \
    && rm -rf /var/lib/apt/lists/*

# Create pi user with sudo access
RUN useradd -m -s /bin/bash pi && \
    echo "pi:raspberry" | chpasswd && \
    usermod -aG sudo pi && \
    echo "pi ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Set up systemd (for service management testing)
RUN systemctl enable ssh

# Create Pi Gateway test directory
WORKDIR /home/pi/pi-gateway

# Copy Pi Gateway scripts
COPY . /home/pi/pi-gateway/
RUN chown -R pi:pi /home/pi/pi-gateway

# Expose SSH port
EXPOSE 22

# Switch to pi user
USER pi

# Set up environment
ENV HOME=/home/pi
ENV USER=pi

# Default command
CMD ["/bin/bash"]