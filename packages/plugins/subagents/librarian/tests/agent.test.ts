import { describe, it, expect, beforeEach } from 'vitest';
import { LibrarianAgent } from '../src/agent.js';

describe('LibrarianAgent', () => {
  let agent: LibrarianAgent;

  beforeEach(() => {
    agent = new LibrarianAgent();
  });

  it('should have correct name and version', () => {
    expect(agent.name).toBe('librarian');
    expect(agent.version).toBe('0.2.0');
  });

  it('should initialize with config', async () => {
    await agent.initialize({ maxResults: 20, outputFormat: 'json' });
    const config = agent.getConfig();
    expect(config.maxResults).toBe(20);
    expect(config.outputFormat).toBe('json');
  });

  it('should reject search before initialization', async () => {
    const response = await agent.search('test query');
    expect(response.success).toBe(false);
    expect(response.error).toBe('Agent not initialized');
  });

  it('should reject search with empty query', async () => {
    await agent.initialize({});
    const response = await agent.search('');
    expect(response.success).toBe(false);
    expect(response.error).toBe('Search query is required');
  });

  it('should search successfully after initialization', async () => {
    await agent.initialize({});
    const response = await agent.search('test query', { package: 'react' });
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });

  it('should query Context7 successfully', async () => {
    await agent.initialize({});
    const response = await agent.query('react', 'hooks');
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });

  it('should reject query with missing params', async () => {
    await agent.initialize({});
    const response = await agent.query('', 'hooks');
    expect(response.success).toBe(false);
    expect(response.error).toBe('Package and query are required');
  });

  it('should websearch successfully', async () => {
    await agent.initialize({});
    const response = await agent.websearch('test query');
    expect(response.success).toBe(true);
  });

  it('should compile knowledge successfully', async () => {
    await agent.initialize({});
    const response = await agent.compile('React Hooks', { package: 'react' });
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });

  it('should manage cache', async () => {
    await agent.initialize({});
    
    // Check cache stats
    const statsResponse = await agent.manageCache('stats');
    expect(statsResponse.success).toBe(true);
    expect(statsResponse.cacheStats).toBeDefined();
    
    // Clear cache
    const clearResponse = await agent.manageCache('clear');
    expect(clearResponse.success).toBe(true);
  });

  it('should manage sources', async () => {
    await agent.initialize({});
    
    const listResponse = await agent.sources('list');
    expect(listResponse.success).toBe(true);
    
    const exportResponse = await agent.sources('export');
    expect(exportResponse.success).toBe(true);
  });

  it('should shutdown correctly', async () => {
    await agent.initialize({});
    await agent.shutdown();
    
    const response = await agent.search('test');
    expect(response.success).toBe(false);
  });

  it('should format results as JSON', async () => {
    await agent.initialize({ outputFormat: 'json' });
    const response = await agent.search('test', { format: 'json', package: 'test' });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(() => JSON.parse(response.content)).not.toThrow();
    }
  });

  it('should format results as markdown', async () => {
    await agent.initialize({ outputFormat: 'markdown' });
    const response = await agent.search('test', { format: 'markdown', package: 'test' });
    expect(response.success).toBe(true);
    if (typeof response.content === 'string') {
      expect(response.content).toContain('# Search Results');
    }
  });

  it('should use cache when enabled', async () => {
    await agent.initialize({ cacheEnabled: true, cacheTTL: 3600 });
    
    // First search
    const response1 = await agent.search('cached query', { package: 'test' });
    expect(response1.success).toBe(true);
    
    // Second search should use cache
    const response2 = await agent.search('cached query', { package: 'test' });
    expect(response2.success).toBe(true);
  });
});
