# Architect Subagent

Architecture analysis, improvement suggestions, and design pattern recommendations.

## Commands

- `analyze_architecture` - Analyze codebase architecture
- `suggest_improvements` - Suggest architecture improvements
- `check_patterns` - Check design patterns usage
- `generate_docs` - Generate architecture documentation

## Usage

```typescript
import { ArchitectAgent } from '@oml/plugin-architect';

const agent = new ArchitectAgent();
await agent.initialize({ analysisLevel: 'deep' });
const result = await agent.analyzeArchitecture('./src');
```
