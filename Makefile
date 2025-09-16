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

cli: ## Launch interactive Pi Gateway CLI
	@./scripts/pi-gateway-cli.sh

vpn-add: ## Add VPN client (usage: make vpn-add CLIENT=name)
	@if [ -z "$(CLIENT)" ]; then echo "$(RED)Usage: make vpn-add CLIENT=client-name$(RESET)"; exit 1; fi
	@sudo ./scripts/vpn-client-manager.sh add $(CLIENT)

vpn-remove: ## Remove VPN client (usage: make vpn-remove CLIENT=name)
	@if [ -z "$(CLIENT)" ]; then echo "$(RED)Usage: make vpn-remove CLIENT=client-name$(RESET)"; exit 1; fi
	@sudo ./scripts/vpn-client-manager.sh remove $(CLIENT)

vpn-list: ## List VPN clients
	@./scripts/vpn-client-manager.sh list

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

test-dry-run: ## Run all scripts in dry-run mode with Pi hardware simulation
	@echo "$(BLUE)Running Pi Gateway scripts in dry-run mode...$(RESET)"
	@echo "$(YELLOW)→ Testing check-requirements.sh$(RESET)"
	@if DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true ./scripts/check-requirements.sh 2>/dev/null | grep -q "SUCCESS\|passed\|completed"; then echo "  $(GREEN)✓$(RESET) check-requirements.sh dry-run passed"; else echo "  $(RED)✗$(RESET) check-requirements.sh dry-run failed"; fi
	@echo "$(YELLOW)→ Testing install-dependencies.sh$(RESET)"
	@if DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true MOCK_SYSTEM=true ./scripts/install-dependencies.sh 2>/dev/null | grep -q "Cleaning up temporary files"; then echo "  $(GREEN)✓$(RESET) install-dependencies.sh dry-run passed"; else echo "  $(RED)✗$(RESET) install-dependencies.sh dry-run failed"; fi
	@echo "$(YELLOW)→ Testing system-hardening.sh$(RESET)"
	@if DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true MOCK_SYSTEM=true ./scripts/system-hardening.sh 2>/dev/null | grep -q "cleanup\|completed\|SUCCESS"; then echo "  $(GREEN)✓$(RESET) system-hardening.sh dry-run passed"; else echo "  $(RED)✗$(RESET) system-hardening.sh dry-run failed"; fi
	@echo "$(GREEN)Dry-run testing complete$(RESET)"

test-dry-run-verbose: ## Run dry-run tests with verbose output
	@echo "$(BLUE)Running verbose dry-run tests...$(RESET)"
	@echo "$(YELLOW)→ check-requirements.sh:$(RESET)"
	@DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true VERBOSE_DRY_RUN=true ./scripts/check-requirements.sh
	@echo "$(YELLOW)→ install-dependencies.sh:$(RESET)"
	@DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true MOCK_SYSTEM=true VERBOSE_DRY_RUN=true ./scripts/install-dependencies.sh
	@echo "$(YELLOW)→ system-hardening.sh:$(RESET)"
	@DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true MOCK_SYSTEM=true VERBOSE_DRY_RUN=true ./scripts/system-hardening.sh

mock-pi-hardware: ## Test with complete Pi hardware simulation
	@echo "$(BLUE)Simulating Raspberry Pi 4 hardware environment...$(RESET)"
	@MOCK_HARDWARE=true MOCK_PI_MODEL="Raspberry Pi 4 Model B Rev 1.4" MOCK_PI_MEMORY_MB=4096 MOCK_PI_STORAGE_GB=64 MOCK_PI_CPU_CORES=4 DRY_RUN=true ./scripts/check-requirements.sh

test-quick: test-dry-run ## Quick development testing (alias for test-dry-run)

test-unit: ## Run BATS unit tests
	@echo "$(BLUE)Running BATS unit tests...$(RESET)"
	@if [ -d "tests/bats-core" ]; then \
		./tests/bats-core/bin/bats tests/unit/*.bats; \
	else \
		echo "$(RED)BATS-core not found. Run 'git submodule update --init' first$(RESET)"; \
	fi

test-integration: ## Run integration tests in QEMU Pi environment
	@echo "$(BLUE)Running integration tests in QEMU Pi environment...$(RESET)"
	@if [ -f "tests/qemu/pi-gateway-test/run-pi-vm.sh" ]; then \
		./tests/bats-core/bin/bats tests/integration/*.bats; \
	else \
		echo "$(RED)QEMU environment not set up. Run 'make setup-qemu' first$(RESET)"; \
	fi

setup-qemu: ## Set up QEMU Pi environment for integration testing
	@echo "$(BLUE)Setting up QEMU Pi environment...$(RESET)"
	@./tests/qemu/setup-pi-vm.sh

test-docker: ## Run integration tests in Docker environment (simple mode)
	@echo "$(BLUE)Running integration tests in Docker environment...$(RESET)"
	@./tests/docker/docker-test.sh run

test-docker-systemd: ## Run integration tests in Docker with full systemd support
	@echo "$(BLUE)Running integration tests in Docker systemd environment...$(RESET)"
	@USE_SIMPLE_MODE=false ./tests/docker/docker-test.sh run

docker-build: ## Build Docker test image
	@echo "$(BLUE)Building Docker test image...$(RESET)"
	@./tests/docker/docker-test.sh build

docker-shell: ## Open shell in Docker test container
	@echo "$(BLUE)Starting interactive shell in Docker container...$(RESET)"
	@./tests/docker/docker-test.sh shell

docker-cleanup: ## Clean up Docker test containers and images
	@echo "$(BLUE)Cleaning up Docker test environment...$(RESET)"
	@./tests/docker/docker-test.sh cleanup

test-all: test-dry-run test-unit ## Run all tests (dry-run + unit)

test-all-integration: test-dry-run test-unit test-docker ## Run all tests including Docker integration

test-all-complete: test-dry-run test-unit test-docker test-docker-systemd ## Run complete test suite (all modes)

format: ## Format shell scripts and fix common issues
	@echo "$(BLUE)Formatting shell scripts...$(RESET)"
	@echo "$(YELLOW)→ Checking script permissions$(RESET)"
	@find scripts/ -name "*.sh" -exec chmod +x {} \;
	@find tests/mocks/ -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@echo "$(YELLOW)→ Removing trailing whitespace$(RESET)"
	@find scripts/ tests/mocks/ -name "*.sh" -exec sed -i.bak 's/[[:space:]]*$$//' {} \; -exec rm {}.bak \;
	@echo "$(YELLOW)→ Ensuring files end with newline$(RESET)"
	@find scripts/ tests/mocks/ -name "*.sh" -exec sh -c 'tail -c1 "$$0" | read -r _ || echo >> "$$0"' {} \;
	@echo "$(GREEN)Code formatting complete$(RESET)"

format-check: ## Check if code needs formatting
	@echo "$(BLUE)Checking code formatting...$(RESET)"
	@scripts_need_formatting=0; \
	for file in $$(find scripts/ tests/mocks/ -name "*.sh" 2>/dev/null); do \
		if [ -f "$$file" ]; then \
			if grep -q '[[:space:]]$$' "$$file" || ! tail -c1 "$$file" | read -r _; then \
				echo "  $(YELLOW)⚠$(RESET) $$file needs formatting"; \
				scripts_need_formatting=1; \
			fi; \
		fi; \
	done; \
	if [ $$scripts_need_formatting -eq 0 ]; then \
		echo "$(GREEN)✓ All scripts are properly formatted$(RESET)"; \
	else \
		echo "$(YELLOW)Run 'make format' to fix formatting issues$(RESET)"; \
		exit 1; \
	fi
