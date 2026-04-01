import { describe, it, expect, beforeEach } from 'vitest';
import { SecurityAuditorAgent } from '../src/agent.js';

describe('SecurityAuditorAgent', () => {
  let agent: SecurityAuditorAgent;

  beforeEach(() => {
    agent = new SecurityAuditorAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('security-auditor');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should audit code', async () => {
    await agent.initialize({});
    const result = await agent.auditCode('./src');
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
