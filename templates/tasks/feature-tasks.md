# Feature Implementation Task Templates
# Copy and customize. Replace [FEATURE_NAME] and workdir paths.

## Plan [FEATURE_NAME]
- workdir: .
- model: opus
- effort: high
- agents: planner, architect
- hooks: standard
- allowedTools: Read Grep Glob Agent

Create a comprehensive implementation plan for [FEATURE_NAME].

Include:
1. Requirements analysis with success criteria
2. Architecture changes with specific file paths
3. Implementation steps broken into phases
4. Testing strategy (unit, integration, E2E)
5. Risks and mitigations
6. Estimated complexity per step

Follow the plan format: Overview, Requirements, Architecture Changes, Implementation Steps (phased), Testing Strategy, Risks.

## Implement [FEATURE_NAME] - Core
- workdir: .
- model: sonnet
- effort: high
- agents: tdd-guide
- hooks: strict
- allowedTools: Read Grep Glob Bash Edit Write Agent

Implement the core functionality for [FEATURE_NAME] using TDD:

1. Write failing tests first (RED)
2. Implement minimal code to pass tests (GREEN)
3. Refactor for clarity and patterns (IMPROVE)
4. Verify 80%+ test coverage

Follow existing project conventions. Prefer extending existing code over rewriting.

## Code Review [FEATURE_NAME]
- workdir: .
- model: sonnet
- effort: high
- agents: code-reviewer
- skills: verification-loop
- hooks: strict
- allowedTools: Read Grep Glob Bash Agent

Review the implementation of [FEATURE_NAME]:
- Code quality (functions <50 lines, files <800 lines)
- Error handling completeness
- Input validation at boundaries
- Test coverage adequacy (80%+)
- Security considerations
- Performance implications
- Adherence to project conventions

Report issues by severity: CRITICAL, HIGH, MEDIUM, LOW.

## Security Review [FEATURE_NAME]
- workdir: .
- model: opus
- effort: high
- agents: security-reviewer
- hooks: strict
- allowedTools: Read Grep Glob Agent

Security review the [FEATURE_NAME] implementation:
- Authentication and authorization checks
- Input validation and sanitization
- SQL injection prevention
- XSS prevention
- Sensitive data handling
- Rate limiting
- Error message information leakage

Focus only on files changed for this feature.
