import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { existsSync, readFileSync, writeFileSync, rmSync, mkdirSync } from 'fs';
import { join } from 'path';

// Mock settings file for testing
const TEST_SETTINGS_DIR = '/tmp/context7-test-settings';
const TEST_SETTINGS_FILE = join(TEST_SETTINGS_DIR, 'settings.json');

// Import functions to test (inline for simplicity)
function loadSettings(settingsPath?: string): Record<string, unknown> {
  const path = settingsPath || TEST_SETTINGS_FILE;
  if (existsSync(path)) {
    try {
      return JSON.parse(readFileSync(path, 'utf-8'));
    } catch {
      return {};
    }
  }
  return {};
}

function saveSettings(settings: Record<string, unknown>, settingsPath?: string): void {
  const path = settingsPath || TEST_SETTINGS_FILE;
  writeFileSync(path, JSON.stringify(settings, null, 2), 'utf-8');
}

describe('Context7 Config', () => {
  beforeEach(() => {
    // Setup test directory
    if (!existsSync(TEST_SETTINGS_DIR)) {
      mkdirSync(TEST_SETTINGS_DIR, { recursive: true });
    }
    writeFileSync(TEST_SETTINGS_FILE, '{}', 'utf-8');
  });

  afterEach(() => {
    // Cleanup
    if (existsSync(TEST_SETTINGS_FILE)) {
      rmSync(TEST_SETTINGS_FILE);
    }
    if (existsSync(TEST_SETTINGS_DIR)) {
      rmSync(TEST_SETTINGS_DIR, { recursive: true, force: true });
    }
  });

  it('should load empty settings if file does not exist', () => {
    const settings = loadSettings('/nonexistent/path.json');
    expect(settings).toEqual({});
  });

  it('should load settings from file', () => {
    const testSettings = {
      model: { name: 'test' },
      mcpServers: { context7: { enabled: true } },
    };
    saveSettings(testSettings);
    
    const loaded = loadSettings();
    expect(loaded.model).toEqual({ name: 'test' });
    expect(loaded.mcpServers).toEqual({ context7: { enabled: true } });
  });

  it('should save settings to file', () => {
    const testSettings = {
      mcpServers: {
        context7: {
          command: 'npx',
          args: ['-y', '@upstash/context7-mcp@latest'],
          enabled: true,
        },
      },
    };
    
    saveSettings(testSettings);
    const content = readFileSync(TEST_SETTINGS_FILE, 'utf-8');
    const parsed = JSON.parse(content);
    
    expect(parsed.mcpServers.context7.command).toBe('npx');
    expect(parsed.mcpServers.context7.enabled).toBe(true);
  });

  it('should handle invalid JSON gracefully', () => {
    writeFileSync(TEST_SETTINGS_FILE, 'invalid json', 'utf-8');
    const settings = loadSettings();
    expect(settings).toEqual({});
  });
});

describe('Context7 MCP Enable/Disable', () => {
  beforeEach(() => {
    if (!existsSync(TEST_SETTINGS_DIR)) {
      mkdirSync(TEST_SETTINGS_DIR, { recursive: true });
    }
    writeFileSync(TEST_SETTINGS_FILE, '{}', 'utf-8');
  });

  afterEach(() => {
    if (existsSync(TEST_SETTINGS_FILE)) {
      rmSync(TEST_SETTINGS_FILE);
    }
    if (existsSync(TEST_SETTINGS_DIR)) {
      rmSync(TEST_SETTINGS_DIR, { recursive: true, force: true });
    }
  });

  it('should enable local mode', async () => {
    // Simulate enable local mode
    const settings = loadSettings();
    const mcpServers = (settings.mcpServers as Record<string, unknown>) || {};
    
    mcpServers.context7 = {
      command: 'npx',
      args: ['-y', '@upstash/context7-mcp@latest'],
      protocol: 'mcp',
      enabled: true,
      trust: false,
    };
    
    settings.mcpServers = mcpServers;
    saveSettings(settings);
    
    const loaded = loadSettings();
    expect(loaded.mcpServers).toBeDefined();
    expect((loaded.mcpServers as Record<string, unknown>).context7).toBeDefined();
  });

  it('should enable remote mode with API key', async () => {
    const settings = loadSettings();
    const mcpServers = (settings.mcpServers as Record<string, unknown>) || {};
    
    mcpServers.context7 = {
      url: 'https://mcp.context7.com/mcp',
      headers: {
        Authorization: 'Bearer sk-test-key',
      },
      protocol: 'mcp',
      enabled: true,
    };
    
    settings.mcpServers = mcpServers;
    saveSettings(settings);
    
    const loaded = loadSettings();
    const context7 = (loaded.mcpServers as Record<string, Record<string, unknown>>).context7;
    expect(context7.url).toBe('https://mcp.context7.com/mcp');
    expect(context7.headers).toBeDefined();
  });

  it('should disable context7', async () => {
    // First enable
    const settings = loadSettings();
    settings.mcpServers = { context7: { enabled: true } };
    saveSettings(settings);
    
    // Then disable
    const loaded = loadSettings();
    const mcpServers = (loaded.mcpServers as Record<string, unknown>) || {};
    if (mcpServers.context7) {
      delete mcpServers.context7;
    }
    loaded.mcpServers = mcpServers;
    saveSettings(loaded);
    
    const final = loadSettings();
    expect((final.mcpServers as Record<string, unknown>)?.context7).toBeUndefined();
  });
});
