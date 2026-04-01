import { describe, it, expect, beforeEach } from 'vitest';
import { CiCdSetupAgent } from '../src/agent.js';

describe('CiCdSetupAgent', () => {
  let agent: CiCdSetupAgent;

  beforeEach(() => { agent = new CiCdSetupAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('ci-cd-setup');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should setup CI', async () => {
    await agent.initialize({});
    const result = await agent.setupCi();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
