# Contributing to Bezgelor

Thank you for your interest in contributing to Bezgelor! This document outlines our development process and guidelines.

## Development Process

This project uses an AI-assisted development workflow built on:

- [Claude Code](https://github.com/anthropics/claude-code) - Anthropic's AI coding assistant
- [Superpowers](https://github.com/obra/superpowers) - Jesse Vincent's skills and workflows for Claude Code
- [Beads](https://github.com/steveyegge/beads) - Steve Yegge's git-native issue tracking

The process is inspired by [Steve Yegge's work on AI-driven development](https://steve-yegge.medium.com/) and emphasizes thorough planning before implementation:

### 1. Brainstorming Phase
Start any significant feature or fix with `/superpowers:brainstorm`. This exploratory phase:
- Gathers requirements and constraints
- Identifies edge cases and potential issues
- Explores architectural options
- Produces a summary for review

Review the brainstorm output and iterate until the problem space is well understood.

### 2. Planning Phase
Move to `/superpowers:write-plan` to create a detailed implementation plan. This phase:
- Breaks work into discrete, testable tasks
- Identifies file changes and dependencies
- Defines acceptance criteria
- Estimates complexity

**Aggressively review and iterate on plans.** A good plan prevents wasted implementation effort.

The implementation plan should be committed to `docs/plans/` alongside the code.

### 3. Issue Tracking
Create [Beads](https://github.com/steveyegge/beads) issues from the plan:
- Each task becomes a trackable issue
- Dependencies between tasks are explicit
- Progress is visible via `bd list` and `bd ready`

### 4. Implementation
Create a feature branch and implement tasks:
- Work through issues systematically
- Run tests after each significant change
- Commit frequently with descriptive messages

### 5. Code Review
Use Claude Code's `/review` command to review changes before merging:
- Run the review at least 3 times to catch issues that emerge after fixes
- Address only issues within the scope of the plan/PR
- Resist scope creep - save unrelated improvements for future work

## Getting Started

1. Fork the repository
2. Clone your fork
3. Run `./scripts/setup.sh` to set up the development environment
4. Create a branch for your changes

## Code Guidelines

[Claude Code](https://github.com/anthropics/claude-code) handles most of this automatically with minor developer oversight:

- **Formatting**: `mix format` applied before commits
- **Testing**: Runs affected tests after changes, not the full suite
- **Commits**: Conventional commit format (`type(scope): description`)
- **Style**: Standard Elixir conventions, pattern matching over conditionals

### Pull Requests
- Reference related issues
- Describe what changed and why
- Ensure all tests pass

## Architecture

See [docs/architecture.md](docs/architecture.md) for system overview. Key principles:
- OTP supervision trees for fault tolerance
- Message passing over shared state
- Per-zone process isolation
- Pure functions for game logic in `bezgelor_core`

## Packet Protocol

WildStar uses continuous bit-packed serialization. See CLAUDE.md for critical details on packet writing.

## Questions?

Open an issue for questions or discussions about potential contributions.

## License

By contributing, you agree that your contributions will be licensed under the AGPL-3.0 license.
