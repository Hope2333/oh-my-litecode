// Events - AI-LTC Bridge event mapping

import type { EventMapping } from './types.js';

const EVENT_MAP: EventMapping[] = [
  {
    transition: 'INIT → EXECUTION',
    hook: 'bridge:execution:start',
    payloadSchema: { sessionId: 'string', goal: 'string', tasks: 'string' },
  },
  {
    transition: 'HANDOFF_READY → EXECUTION',
    hook: 'bridge:execution:start',
    payloadSchema: { sessionId: 'string', goal: 'string', tasks: 'string' },
  },
  {
    transition: 'EXECUTION → REVIEW',
    hook: 'bridge:review:start',
    payloadSchema: { sessionId: 'string', phase: 'string', artifacts: 'string' },
  },
  {
    transition: 'REVIEW → OPTIMIZER',
    hook: 'bridge:optimize:start',
    payloadSchema: { sessionId: 'string', reviewFindings: 'string' },
  },
  {
    transition: 'OPTIMIZER → CHECKPOINT',
    hook: 'bridge:checkpoint:create',
    payloadSchema: { sessionId: 'string', summary: 'string', metrics: 'string' },
  },
  {
    transition: 'REVIEW → EXECUTION',
    hook: 'bridge:blocked:resolve',
    payloadSchema: { sessionId: 'string', resolution: 'string' },
  },
  {
    transition: 'EXECUTION → CHECKPOINT',
    hook: 'bridge:done:notify',
    payloadSchema: { sessionId: 'string', finalSummary: 'string' },
  },
  {
    transition: 'Any → BLOCKED',
    hook: 'bridge:blocked:notify',
    payloadSchema: { sessionId: 'string', blocker: 'string', context: 'string' },
  },
];

export class EventMapper {
  private readonly eventMap: ReadonlyArray<EventMapping>;

  constructor(eventMap?: EventMapping[]) {
    this.eventMap = eventMap ? [...eventMap] : EVENT_MAP;
  }

  getEventMap(): ReadonlyArray<EventMapping> {
    return this.eventMap;
  }

  mapTransitionToHook(transition: string): EventMapping | undefined {
    return this.eventMap.find((m) => m.transition === transition);
  }

  mapHookToTransition(hook: string): string | undefined {
    return this.eventMap.find((m) => m.hook === hook)?.transition;
  }

  getPayloadSchema(hook: string): Record<string, string> | undefined {
    return this.eventMap.find((m) => m.hook === hook)?.payloadSchema;
  }

  findWildcardMapping(phase: string): EventMapping | undefined {
    const bridgeMappings = this.eventMap.filter((m) => m.hook.startsWith('bridge:'));

    for (const m of bridgeMappings) {
      const parts = m.transition.split(' → ');
      const target = parts[1];
      if (target === phase) return m;
    }

    const blockedMapping = bridgeMappings.find((m) => {
      const parts = m.transition.split(' → ');
      return parts[1] === 'BLOCKED';
    });
    if (blockedMapping) return blockedMapping;

    return undefined;
  }
}

const defaultMapper = new EventMapper();

export function getEventMap(): EventMapping[] {
  return [...defaultMapper.getEventMap()];
}

export function mapTransitionToHook(transition: string): EventMapping | undefined {
  return defaultMapper.mapTransitionToHook(transition);
}

export function mapHookToTransition(hook: string): string | undefined {
  return defaultMapper.mapHookToTransition(hook);
}
