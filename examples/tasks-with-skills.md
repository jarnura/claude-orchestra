# Tasks with ECC Skill Injection
# These tasks demonstrate skill-enhanced execution.
# Skill reference material is appended to the system prompt.

## Backend Review with Skills
- workdir: .
- model: sonnet
- effort: high
- agents: code-reviewer
- skills: backend-patterns
- hooks: standard
- allowedTools: Read Grep Glob Agent

Review this project's backend code using backend-patterns skill reference.
Check for proper API design, repository patterns, error handling,
and consistent response formats.

## TDD Implementation with Skills
- workdir: .
- model: sonnet
- effort: high
- agents: tdd-guide
- skills: verification-loop
- hooks: strict
- allowedTools: Read Grep Glob Bash Edit Write Agent

Add comprehensive test coverage to this project following TDD methodology.
Use the verification-loop skill to ensure all quality gates pass:
build, type-check, lint, test (80%+), security scan.
