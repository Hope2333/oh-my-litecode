import { describe, it, expect, beforeEach } from 'vitest';
import { DockerSetupAgent } from '../src/agent.js';

describe('DockerSetupAgent', () => {
  let agent: DockerSetupAgent;

  beforeEach(() => { agent = new DockerSetupAgent(); });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('docker-setup');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({});
    expect(agent.getConfig()).toBeDefined();
  });

  it('should setup Docker', async () => {
    await agent.initialize({});
    const result = await agent.setupDocker();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
