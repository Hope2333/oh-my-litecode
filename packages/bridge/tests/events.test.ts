import { describe, it, expect } from 'vitest';
import { EventMapper, getEventMap, mapTransitionToHook, mapHookToTransition } from '../src/events.js';

describe('EventMapper class', () => {
  const mapper = new EventMapper();

  describe('getEventMap()', () => {
    it('returns all 8 mappings', () => {
      const mappings = mapper.getEventMap();
      expect(mappings).toHaveLength(8);
    });

    it('returns a readonly array', () => {
      const mappings = mapper.getEventMap();
      expect(Array.isArray(mappings)).toBe(true);
    });
  });

  describe('mapTransitionToHook()', () => {
    it('returns correct mapping for EXECUTION → REVIEW', () => {
      const result = mapper.mapTransitionToHook('EXECUTION → REVIEW');
      expect(result).toBeDefined();
      expect(result!.hook).toBe('bridge:review:start');
    });

    it('returns undefined for nonexistent transition', () => {
      const result = mapper.mapTransitionToHook('nonexistent');
      expect(result).toBeUndefined();
    });

    it('returns correct mapping for INIT → EXECUTION', () => {
      const result = mapper.mapTransitionToHook('INIT → EXECUTION');
      expect(result).toBeDefined();
      expect(result!.hook).toBe('bridge:execution:start');
    });

    it('returns correct mapping for wildcard Any → BLOCKED', () => {
      const result = mapper.mapTransitionToHook('Any → BLOCKED');
      expect(result).toBeDefined();
      expect(result!.hook).toBe('bridge:blocked:notify');
    });
  });

  describe('mapHookToTransition()', () => {
    it('returns correct transition for bridge:review:start', () => {
      const result = mapper.mapHookToTransition('bridge:review:start');
      expect(result).toBe('EXECUTION → REVIEW');
    });

    it('returns undefined for unknown hook', () => {
      const result = mapper.mapHookToTransition('bridge:unknown:hook');
      expect(result).toBeUndefined();
    });

    it('returns correct transition for bridge:optimize:start', () => {
      const result = mapper.mapHookToTransition('bridge:optimize:start');
      expect(result).toBe('REVIEW → OPTIMIZER');
    });
  });

  describe('getPayloadSchema()', () => {
    it('returns correct schema for bridge:review:start', () => {
      const schema = mapper.getPayloadSchema('bridge:review:start');
      expect(schema).toEqual({
        sessionId: 'string',
        phase: 'string',
        artifacts: 'string',
      });
    });

    it('returns correct schema for bridge:execution:start', () => {
      const schema = mapper.getPayloadSchema('bridge:execution:start');
      expect(schema).toEqual({
        sessionId: 'string',
        goal: 'string',
        tasks: 'string',
      });
    });

    it('returns undefined for unknown hook', () => {
      const schema = mapper.getPayloadSchema('bridge:nonexistent');
      expect(schema).toBeUndefined();
    });
  });

  describe('findWildcardMapping()', () => {
    it('finds mappings targeting REVIEW phase', () => {
      const result = mapper.findWildcardMapping('REVIEW');
      expect(result).toBeDefined();
      expect(result!.transition).toBe('EXECUTION → REVIEW');
    });

    it('finds mappings targeting BLOCKED phase', () => {
      const result = mapper.findWildcardMapping('BLOCKED');
      expect(result).toBeDefined();
      expect(result!.transition).toBe('Any → BLOCKED');
    });

    it('falls back to BLOCKED mapping for unknown phases', () => {
      const result = mapper.findWildcardMapping('NONEXISTENT');
      expect(result).toBeDefined();
      expect(result!.transition).toBe('Any → BLOCKED');
    });
  });

  describe('custom event map', () => {
    it('accepts custom mappings via constructor', () => {
      const customMapper = new EventMapper([
        { transition: 'A → B', hook: 'custom:hook', payloadSchema: { foo: 'string' } },
      ]);
      expect(customMapper.getEventMap()).toHaveLength(1);
      expect(customMapper.mapTransitionToHook('A → B')!.hook).toBe('custom:hook');
    });
  });
});

describe('standalone functions', () => {
  it('getEventMap() returns all 8 mappings', () => {
    expect(getEventMap()).toHaveLength(8);
  });

  it('mapTransitionToHook() returns correct mapping', () => {
    const result = mapTransitionToHook('EXECUTION → REVIEW');
    expect(result).toBeDefined();
    expect(result!.hook).toBe('bridge:review:start');
  });

  it('mapHookToTransition() returns correct transition', () => {
    const result = mapHookToTransition('bridge:review:start');
    expect(result).toBe('EXECUTION → REVIEW');
  });
});
