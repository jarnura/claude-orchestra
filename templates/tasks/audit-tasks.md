# Audit Task Templates
# Copy and customize for your project. Replace workdir paths.

## Security Audit
- workdir: .
- model: opus
- effort: high
- agents: security-reviewer
- hooks: strict
- allowedTools: Read Grep Glob Agent

Perform a comprehensive security audit of this codebase.
Focus on OWASP Top 10 vulnerabilities:
- SQL injection and parameterized queries
- XSS prevention and output encoding
- Authentication and authorization flaws
- Sensitive data exposure (hardcoded secrets, credentials in logs)
- CSRF protection
- Rate limiting on API endpoints
- Input validation at system boundaries

Report findings with severity (CRITICAL/HIGH/MEDIUM/LOW), file paths, and recommended fixes.

## Code Quality Review
- workdir: .
- model: sonnet
- effort: high
- agents: code-reviewer
- hooks: standard
- allowedTools: Read Grep Glob Agent

Review the codebase for code quality issues:
- Functions exceeding 50 lines
- Files exceeding 800 lines
- Deep nesting (>4 levels)
- Duplicated code blocks
- Missing error handling
- Hardcoded values that should be constants
- Mutation of shared state (prefer immutable patterns)
- Missing input validation

Report findings with file paths and specific line references.

## Architecture Review
- workdir: .
- model: opus
- effort: high
- agents: architect
- hooks: standard
- allowedTools: Read Grep Glob Agent

Review the system architecture for:
- Separation of concerns and module boundaries
- API design consistency
- Database schema and query patterns (N+1 queries, missing indices)
- Error handling strategy consistency
- Configuration management
- Dependency injection and testability
- Scalability concerns

Produce an Architecture Decision Record (ADR) format report.

## Performance Audit
- workdir: .
- model: sonnet
- effort: high
- agents: code-reviewer
- skills: backend-patterns
- hooks: standard
- allowedTools: Read Grep Glob Bash Agent

Audit for performance issues:
- N+1 database queries
- Missing database indices
- Unbounded queries (missing LIMIT/pagination)
- Memory leaks and resource cleanup
- Synchronous operations that should be async
- Missing caching opportunities
- Large payload responses without pagination

Include specific file paths and recommended optimizations.

## Database Review
- workdir: .
- model: opus
- effort: high
- agents: database-reviewer
- hooks: standard
- allowedTools: Read Grep Glob Agent

Review database layer for:
- Schema design and normalization
- Missing indices for common query patterns
- N+1 query patterns in ORM usage
- Connection pool configuration
- Migration safety (backwards compatible?)
- Query performance (explain plans where possible)
- Data integrity constraints

Report with specific queries, tables, and recommended changes.
