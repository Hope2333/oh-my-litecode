// Adapters — Platform adapter interface and registry for AI-LTC Bridge.

export interface PlatformAdapter {
  name: string;
  version: string;
  initialize(): Promise<void>;
  teardown(): Promise<void>;
  syncState(phase: string): Promise<void>;
  getState(): Promise<string | null>;
  forwardEvent(event: { type: string; payload: Record<string, unknown> }): Promise<void>;
  getCapabilities(): {
    supportsRealtime: boolean;
    supportsHistory: boolean;
    supportsContext: boolean;
  };
}

export class AdapterRegistry {
  private adapters: Map<string, PlatformAdapter> = new Map();
  private activeName: string | null = null;

  register(adapter: PlatformAdapter): void {
    this.adapters.set(adapter.name, adapter);
  }

  get(name: string): PlatformAdapter | undefined {
    return this.adapters.get(name);
  }

  list(): PlatformAdapter[] {
    return Array.from(this.adapters.values());
  }

  getActive(): PlatformAdapter | null {
    if (!this.activeName) return null;
    return this.adapters.get(this.activeName) ?? null;
  }

  setActive(name: string): void {
    if (!this.adapters.has(name)) {
      throw new Error(`Adapter "${name}" not registered`);
    }
    this.activeName = name;
  }
}

export const registry = new AdapterRegistry();
