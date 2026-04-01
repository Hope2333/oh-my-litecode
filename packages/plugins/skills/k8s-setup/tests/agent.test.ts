import { describe, it, expect, beforeEach } from 'vitest';
import { K8sSetupAgent } from '../src/agent.js';

describe('K8sSetupAgent', () => {
  let agent: K8sSetupAgent;

  beforeEach(() => { agent = new K8sSetupAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('k8s-setup');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should setup K8s', async () => {
    await agent.initialize({});
    const result = await agent.setupK8s();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
