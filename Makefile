.PHONY: help install setup test clean lint check validate deploy
.DEFAULT_GOAL := help

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RESET := \033[0m

# Configuration
CONFIG_DIR := config
SCRIPTS_DIR := scripts
DOCS_DIR := docs
ASSETS_DIR := assets

help: ## Show this help message
	@echo "$(BLUE)Pi Gateway - Homelab Bootstrap$(RESET)"
	@echo ""
	@echo "$(GREEN)Available targets:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { \
		printf "  $(YELLOW)%-15s$(RESET) %s\n", $$1, $$2 \
	}' $(MAKEFILE_LIST)

check: ## Check system requirements and dependencies
	@echo "$(BLUE)Checking system requirements...$(RESET)"
	@./scripts/check-requirements.sh

validate: ## Validate configuration files and scripts
	@echo "$(BLUE)Validating configuration and scripts...$(RESET)"
	@find $(SCRIPTS_DIR) -name "*.sh" -exec shellcheck {} \;
	@echo "$(GREEN)Validation complete$(RESET)"

setup: check ## Run the main setup script (must be run on target Pi)
	@echo "$(BLUE)Starting Pi Gateway setup...$(RESET)"
	@sudo ./setup.sh

install: setup ## Alias for setup

test: ## Run tests and validation
	@echo "$(BLUE)Running tests...$(RESET)"
	@$(MAKE) validate
	@if [ -f "tests/run-tests.sh" ]; then ./tests/run-tests.sh; fi

lint: ## Check script formatting and best practices
	@echo "$(BLUE)Linting scripts...$(RESET)"
	@find $(SCRIPTS_DIR) -name "*.sh" -exec shellcheck {} \;
	@find . -name "*.sh" -exec shellcheck {} \;

clean: ## Clean up temporary files and generated configs
	@echo "$(BLUE)Cleaning up...$(RESET)"
	@find . -name "*.tmp" -delete
	@find . -name "*.temp" -delete
	@find . -name "*.bak" -delete
	@rm -rf $(CONFIG_DIR)/generated/
	@echo "$(GREEN)Cleanup complete$(RESET)"

backup-config: ## Backup existing system configurations before setup
	@echo "$(BLUE)Backing up system configurations...$(RESET)"
	@mkdir -p backups/$(shell date +%Y%m%d_%H%M%S)
	@if [ -f /etc/ssh/sshd_config ]; then cp /etc/ssh/sshd_config backups/$(shell date +%Y%m%d_%H%M%S)/; fi
	@if [ -d /etc/wireguard ]; then cp -r /etc/wireguard backups/$(shell date +%Y%m%d_%H%M%S)/; fi
	@echo "$(GREEN)Backup complete$(RESET)"

generate-keys: ## Generate SSH and WireGuard keys
	@echo "$(BLUE)Generating keys...$(RESET)"
	@./scripts/generate-keys.sh

status: ## Check status of Pi Gateway services
	@echo "$(BLUE)Checking service status...$(RESET)"
	@systemctl status ssh || true
	@systemctl status wg-quick@wg0 || true
	@systemctl status vncserver-x11-serviced || true

logs: ## Show recent logs from Pi Gateway services
	@echo "$(BLUE)Recent service logs:$(RESET)"
	@echo "$(YELLOW)SSH:$(RESET)"
	@journalctl -u ssh --no-pager -n 20 || true
	@echo "$(YELLOW)WireGuard:$(RESET)"
	@journalctl -u wg-quick@wg0 --no-pager -n 20 || true

docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(RESET)"
	@if [ -f "scripts/generate-docs.sh" ]; then ./scripts/generate-docs.sh; fi

structure: ## Create recommended directory structure
	@echo "$(BLUE)Creating project structure...$(RESET)"
	@mkdir -p $(SCRIPTS_DIR) $(CONFIG_DIR)/{wireguard,ssh,vnc,ddns} $(DOCS_DIR) assets extensions tests backups
	@echo "$(GREEN)Directory structure created$(RESET)"

install-deps: ## Install development dependencies (shellcheck, etc.)
	@echo "$(BLUE)Installing development dependencies...$(RESET)"
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y shellcheck; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install shellcheck; \
	else \
		echo "$(RED)Package manager not found. Please install shellcheck manually.$(RESET)"; \
	fi

dev-setup: install-deps structure ## Set up development environment
	@echo "$(GREEN)Development environment ready$(RESET)"