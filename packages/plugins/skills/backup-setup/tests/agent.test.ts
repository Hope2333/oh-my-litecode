import { describe, it, expect, beforeEach } from 'vitest';
import { BackupSetupAgent } from '../src/agent.js';

describe('BackupSetupAgent', () => {
  let agent: BackupSetupAgent;

  beforeEach(() => {
    agent = new BackupSetupAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('backup-setup');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({ schedule: 'weekly' });
    expect(agent.getConfig()).toBeDefined();
  });

  it('should setup backup', async () => {
    await agent.initialize({});
    const result = await agent.setupBackup();
    expect(result.success).toBe(true);
  });

  it('should configure schedule', async () => {
    await agent.initialize({});
    const result = await agent.configureSchedule();
    expect(result.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
  });
});
