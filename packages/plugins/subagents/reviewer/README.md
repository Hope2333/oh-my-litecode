# Reviewer Subagent

Code review, security auditing, style checking, and best practices validation.

## Features

- **Code Style Checking**: Naming conventions, indentation, line length
- **Security Vulnerability Scanning**: Injection, XSS, hardcoded secrets
- **Performance Issue Detection**: Inefficient loops, memory leaks
- **Best Practices Validation**: Error handling, logging, documentation
- **Structured Report Generation**: JSON, Markdown, Text formats

## Commands

- `code` - Comprehensive code review (all checks)
- `security` - Security vulnerability audit
- `style` - Code style and formatting check
- `performance` - Performance issue analysis
- `best-practices` - Best practices compliance check
- `report` - Generate structured review report

## Usage

```typescript
import { ReviewerAgent } from '@oml/plugin-reviewer';

const agent = new ReviewerAgent();
await agent.initialize({ maxIssues: 100, strictMode: false });

// Comprehensive code review
const result = await agent.code('./src');

// Security audit
const securityResult = await agent.security('./src');

// Style check
const styleResult = await agent.style('./src', { statsOnly: true });

// Generate report
const report = await agent.report('./src', { format: 'json' });
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| outputFormat | string | 'markdown' | Output format |
| maxIssues | number | 100 | Maximum issues to report |
| excludePatterns | string[] | [...] | Exclude patterns |
| securityEnabled | boolean | true | Enable security checks |
| styleEnabled | boolean | true | Enable style checks |
| performanceEnabled | boolean | true | Enable performance checks |
| bestPracticesEnabled | boolean | true | Enable best practices checks |
| strictMode | boolean | false | Strict mode (fail on critical) |

## Severity Levels

- `critical` - Must fix immediately
- `high` - Should fix soon
- `medium` - Consider fixing
- `low` - Minor issue
- `info` - Suggestion

## License

MIT
