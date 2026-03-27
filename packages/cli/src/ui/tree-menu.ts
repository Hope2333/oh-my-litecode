/**
 * Tree Menu UI - OML CLI
 * 
 * Tree-based menu for help system.
 */

export interface MenuNode {
  name: string;
  description: string;
  children?: MenuNode[];
  action?: () => Promise<void>;
}

export interface TreeMenuOptions {
  title?: string;
  indent?: string;
  showNumbers?: boolean;
}

export class TreeMenu {
  private nodes: MenuNode[];
  private selected: number = 0;
  private options: TreeMenuOptions;

  constructor(nodes: MenuNode[], options?: TreeMenuOptions) {
    this.nodes = nodes;
    this.options = {
      title: 'Menu',
      indent: '  ',
      showNumbers: true,
      ...options,
    };
  }

  render(): void {
    console.log(`\n${this.options.title}`);
    console.log('='.repeat(50));
    this.renderNodes(this.nodes, 0);
    console.log('='.repeat(50));
  }

  private renderNodes(nodes: MenuNode[], depth: number): void {
    const indent = this.options.indent!.repeat(depth);
    
    nodes.forEach((node, index) => {
      const num = this.options.showNumbers ? `${index + 1}. ` : '';
      console.log(`${indent}${num}${node.name} - ${node.description}`);
      
      if (node.children) {
        this.renderNodes(node.children, depth + 1);
      }
    });
  }

  select(index: number): MenuNode | null {
    if (index >= 0 && index < this.nodes.length) {
      this.selected = index;
      return this.nodes[index];
    }
    return null;
  }

  async execute(): Promise<void> {
    const node = this.nodes[this.selected];
    if (node?.action) {
      await node.action();
    }
  }

  getSelected(): MenuNode | null {
    return this.nodes[this.selected] || null;
  }
}

/**
 * Help System
 */
export class HelpSystem {
  private mainMenu: TreeMenu;

  constructor() {
    this.mainMenu = new TreeMenu(this.getMainMenu(), { title: 'OML Help' });
  }

  private getMainMenu(): MenuNode[] {
    return [
      {
        name: 'qwen',
        description: 'Qwen agent controller',
        children: this.getQwenMenu(),
      },
      {
        name: 'session',
        description: 'Session management',
        children: this.getSessionMenu(),
      },
      {
        name: 'config',
        description: 'Configuration management',
      },
      {
        name: 'keys',
        description: 'API key management',
      },
      {
        name: 'mcp',
        description: 'MCP services',
      },
      {
        name: 'extensions',
        description: 'Extension management',
      },
    ];
  }

  private getQwenMenu(): MenuNode[] {
    return [
      { name: 'chat', description: 'Start chat session' },
      { name: 'session', description: 'Manage sessions' },
      { name: 'config', description: 'Manage configuration' },
      { name: 'keys', description: 'Manage API keys' },
      { name: 'mcp', description: 'Manage MCP services' },
      { name: 'help', description: 'Show Qwen help' },
    ];
  }

  private getSessionMenu(): MenuNode[] {
    return [
      { name: 'list', description: 'List sessions' },
      { name: 'show', description: 'Show session details' },
      { name: 'switch', description: 'Switch to session' },
      { name: 'create', description: 'Create new session' },
      { name: 'delete', description: 'Delete session' },
    ];
  }

  showMainHelp(): void {
    this.mainMenu.render();
  }

  showCommandHelp(command: string): void {
    const menu = new TreeMenu(this.getMainMenu(), { title: `OML Help: ${command}` });
    menu.render();
  }

  showSubcommandHelp(command: string, subcommand: string): void {
    console.log(`\nHelp: ${command} ${subcommand}`);
    console.log('='.repeat(50));
    console.log(`Usage: oml ${command} ${subcommand} [options]`);
    console.log('='.repeat(50));
  }
}
