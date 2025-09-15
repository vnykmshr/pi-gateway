# Contributing to Pi Gateway

Thank you for your interest in contributing to Pi Gateway! This document provides guidelines for contributing to the project.

## Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/vnykmshr/pi-gateway.git
   cd pi-gateway
   ```

2. **Set up development environment**:
   ```bash
   make dev-setup
   ```

3. **Validate your setup**:
   ```bash
   make validate
   ```

## Contribution Process

1. **Fork the repository** on GitHub
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following our coding standards
4. **Test your changes**:
   ```bash
   make test
   make validate
   ```
5. **Commit your changes**:
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```
6. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
7. **Create a Pull Request** on GitHub

## Coding Standards

### Shell Scripts
- Use `#!/bin/bash` shebang
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use `shellcheck` for linting (included in `make validate`)
- Include error handling and logging
- Use descriptive function and variable names

### Configuration Files
- Use clear, documented configuration templates
- Include example values with explanations
- Separate sensitive data (use environment variables)

### Documentation
- Update relevant documentation for any changes
- Use clear, concise language
- Include examples where helpful
- Update README.md if adding new features

## Commit Message Format

We follow conventional commits format:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (no functional changes)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

Examples:
- `feat(vpn): add WireGuard client configuration generator`
- `fix(ssh): resolve permission issues with key generation`
- `docs(readme): update installation instructions`

## Testing

### Before Submitting
- Run `make validate` to check script syntax
- Test scripts in a clean environment when possible
- Verify documentation updates are accurate
- Ensure new features include appropriate error handling

### Types of Tests
- **Syntax validation**: Using shellcheck
- **Integration tests**: Test complete workflows
- **Security checks**: Validate security configurations

## Security Considerations

- Never commit sensitive data (keys, passwords, etc.)
- Follow security best practices for all scripts
- Test security configurations thoroughly
- Document security implications of changes

## Documentation

- Update relevant documentation for any changes
- Include usage examples for new features
- Keep documentation current with code changes
- Use clear, beginner-friendly language

## Issues and Feature Requests

- Use GitHub Issues for bugs and feature requests
- Provide clear reproduction steps for bugs
- Include system information when relevant
- Search existing issues before creating new ones

## Questions?

If you have questions about contributing, feel free to:
- Open an issue for discussion
- Review existing documentation
- Check the project's README.md

We appreciate your contributions to making Pi Gateway better!