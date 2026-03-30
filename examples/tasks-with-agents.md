# Tasks with ECC Agent Injection
# These tasks demonstrate agent-enhanced execution.
# Agents are injected into the system prompt automatically.

## Security Audit with Agent
- workdir: .
- model: opus
- effort: high
- agents: security-reviewer
- hooks: strict
- allowedTools: Read Grep Glob Agent

Audit this project for security vulnerabilities.
Focus on hardcoded secrets, SQL injection, XSS, and authentication issues.
Report findings with severity levels.

## Code Review with Agent
- workdir: .
- model: sonnet
- effort: high
- agents: code-reviewer
- hooks: standard
- allowedTools: Read Grep Glob Agent

Review this project's code quality.
Check for large functions, deep nesting, missing error handling,
and adherence to immutable patterns.

## Architecture Review with Agent
- workdir: .
- model: opus
- effort: high
- agents: architect
- hooks: standard
- allowedTools: Read Grep Glob Agent

Review the project's architecture.
Identify design patterns in use, potential anti-patterns,
and suggest improvements for scalability and maintainability.
