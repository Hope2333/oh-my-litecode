/**
 * TUI Components - OML Modules
 */

import { TerminalRenderer } from './renderer.js';
import type { TextStyle, BoxOptions, ButtonOptions, InputOptions, ListOptions, MenuOptions, ListItem } from './types.js';

export class Box {
  options: BoxOptions;
  renderer: TerminalRenderer;
  constructor(renderer: TerminalRenderer, options: BoxOptions) {
    this.renderer = renderer;
    this.options = options;
  }
  render(): void {
    const { x, y, width, height, title, border = 'single', style } = this.options;
    if (border === 'none') { if (title) this.renderer.drawText(title, x + 2, y, style); return; }
    const corners = this.getCorners(border);
    this.renderer.drawText(corners.tl, x, y, style);
    this.renderer.drawText(corners.tr, x + width - 1, y, style);
    this.renderer.drawText(corners.bl, x, y + height - 1, style);
    this.renderer.drawText(corners.br, x + width - 1, y + height - 1, style);
    for (let i = 1; i < width - 1; i++) {
      this.renderer.drawText(corners.h, x + i, y, style);
      this.renderer.drawText(corners.h, x + i, y + height - 1, style);
    }
    for (let i = 1; i < height - 1; i++) {
      this.renderer.drawText(corners.v, x, y + i, style);
      this.renderer.drawText(corners.v, x + width - 1, y + i, style);
    }
    if (title) this.renderer.drawText(` ${title} `, x + 2, y, style);
  }
  private getCorners(border: string): { tl: string; tr: string; bl: string; br: string; h: string; v: string } {
    switch (border) {
      case 'double': return { tl: '╔', tr: '╗', bl: '╚', br: '╝', h: '═', v: '║' };
      case 'rounded': return { tl: '╭', tr: '╮', bl: '╰', br: '╯', h: '─', v: '│' };
      default: return { tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│' };
    }
  }
}

export class Button {
  options: ButtonOptions;
  renderer: TerminalRenderer;
  private onClickHandler?: () => void;
  constructor(renderer: TerminalRenderer, options: ButtonOptions) {
    this.renderer = renderer;
    this.options = options;
    this.onClickHandler = options.onClick;
  }
  render(): void {
    const { label, x, y, width = label.length + 4, selected = false } = this.options;
    const style: TextStyle = selected ? { fg: 'black', bg: 'white', style: 'bold' } : { fg: 'cyan' };
    const padding = width - label.length;
    const leftPad = Math.floor(padding / 2);
    const rightPad = padding - leftPad;
    this.renderer.drawText('┌' + ' '.repeat(leftPad) + label + ' '.repeat(rightPad) + '┐', x, y, style);
  }
  click(): void { this.onClickHandler?.(); }
}

export class Input {
  options: InputOptions;
  renderer: TerminalRenderer;
  value: string;
  cursorPos: number;
  constructor(renderer: TerminalRenderer, options: InputOptions) {
    this.renderer = renderer;
    this.options = options;
    this.value = options.value || '';
    this.cursorPos = this.value.length;
  }
  render(): void {
    const { label, x, y, width, password = false } = this.options;
    let inputX = x;
    if (label) { this.renderer.drawText(label, x, y); inputX = x + label.length + 1; }
    const displayValue = password ? '•'.repeat(this.value.length) : this.value;
    this.renderer.drawText(displayValue + ' '.repeat(width - displayValue.length), inputX, y, { fg: 'yellow' });
  }
  setValue(value: string): void { this.value = value; this.cursorPos = value.length; }
  getValue(): string { return this.value; }
  handleKey(key: string): boolean {
    if (key === '\x7f' || key === '\b') { if (this.cursorPos > 0) { this.value = this.value.slice(0, this.cursorPos - 1) + this.value.slice(this.cursorPos); this.cursorPos--; } return true; }
    if (key === '\x1b[D') { if (this.cursorPos > 0) this.cursorPos--; return true; }
    if (key === '\x1b[C') { if (this.cursorPos < this.value.length) this.cursorPos++; return true; }
    if (key.length === 1 && key >= ' ') { this.value = this.value.slice(0, this.cursorPos) + key + this.value.slice(this.cursorPos); this.cursorPos++; return true; }
    return false;
  }
}

export class List {
  options: ListOptions;
  renderer: TerminalRenderer;
  selectedIndex: number;
  scrollOffset: number;
  constructor(renderer: TerminalRenderer, options: ListOptions) {
    this.renderer = renderer;
    this.options = options;
    this.selectedIndex = options.selectedIndex || 0;
    this.scrollOffset = 0;
  }
  render(): void {
    const { x, y, width, height, items } = this.options;
    if (this.selectedIndex < this.scrollOffset) this.scrollOffset = this.selectedIndex;
    else if (this.selectedIndex >= this.scrollOffset + height) this.scrollOffset = this.selectedIndex - height + 1;
    this.renderer.drawBox(x, y, width, height + 2);
    for (let i = 0; i < Math.min(height, items.length - this.scrollOffset); i++) {
      const itemIndex = i + this.scrollOffset;
      const item = items[itemIndex];
      const marker = itemIndex === this.selectedIndex ? '▶ ' : '  ';
      const style: TextStyle = item.selected ? { fg: 'black', bg: 'white' } : itemIndex === this.selectedIndex ? { fg: 'green' } : {};
      this.renderer.drawText((marker + item.label).substring(0, width - 2), x + 1, y + i + 1, style);
    }
  }
  select(index: number): void {
    if (index >= 0 && index < this.options.items.length) {
      this.selectedIndex = index;
      this.options.items.forEach((item, i) => { item.selected = i === index; });
    }
  }
  getSelected(): ListItem | null { return this.options.items[this.selectedIndex] || null; }
  moveUp(): void { if (this.selectedIndex > 0) this.select(this.selectedIndex - 1); }
  moveDown(): void { if (this.selectedIndex < this.options.items.length - 1) this.select(this.selectedIndex + 1); }
  click(): void { /* handled by parent */ }
}

export class Menu {
  options: MenuOptions;
  renderer: TerminalRenderer;
  selectedIndex: number;
  constructor(renderer: TerminalRenderer, options: MenuOptions) {
    this.renderer = renderer;
    this.options = options;
    this.selectedIndex = 0;
  }
  render(): void {
    const { x, y, items, title } = this.options;
    if (title) this.renderer.drawText(title, x, y, { style: 'bold', fg: 'cyan' });
    const menuY = title ? y + 1 : y;
    const menuText = items.map((item, i) => {
      const shortcut = item.shortcut ? `[${item.shortcut}]` : '';
      return i === this.selectedIndex ? `▶ ${item.label} ${shortcut}` : `  ${item.label} ${shortcut}`;
    }).join(' | ');
    this.renderer.drawText(menuText, x, menuY, { fg: 'yellow' });
  }
  select(index: number): void { if (index >= 0 && index < this.options.items.length) this.selectedIndex = index; }
  getSelected(): { label: string; shortcut?: string; action?: () => void } | null { return this.options.items[this.selectedIndex] || null; }
  activate(): void { const s = this.getSelected(); s?.action?.(); }
  moveLeft(): void { if (this.selectedIndex > 0) this.selectedIndex--; }
  moveRight(): void { if (this.selectedIndex < this.options.items.length - 1) this.selectedIndex++; }
}

export class App {
  renderer: TerminalRenderer;
  components: Array<Box | Button | Input | List | Menu>;
  running: boolean;
  focusedComponent: any;
  constructor(renderer?: TerminalRenderer) {
    this.renderer = renderer || new TerminalRenderer();
    this.components = [];
    this.running = false;
    this.focusedComponent = null;
  }
  add(component: Box | Button | Input | List | Menu): void { this.components.push(component); }
  render(): void {
    this.renderer.clear();
    for (const component of this.components) component.render();
    this.renderer.render();
  }
  async run(): Promise<void> {
    this.running = true;
    this.renderer.hideCursor();
    this.renderer.clear();
    while (this.running) { this.render(); const key = await this.renderer.readKey(); this.handleKey(key); }
    this.renderer.showCursor();
  }
  handleKey(key: string): void {
    if (key === 'q' || key === '\x03') { this.running = false; return; }
    if (this.focusedComponent?.handleKey) this.focusedComponent.handleKey(key);
    if (this.focusedComponent instanceof List) {
      if (key === '\x1b[A') this.focusedComponent.moveUp();
      if (key === '\x1b[B') this.focusedComponent.moveDown();
    }
    if (this.focusedComponent instanceof Menu) {
      if (key === '\x1b[A' || key === '\x1b[D') this.focusedComponent.moveLeft();
      if (key === '\x1b[B' || key === '\x1b[C') this.focusedComponent.moveRight();
      if (key === '\n' || key === '\r') this.focusedComponent.activate();
    }
  }
  stop(): void { this.running = false; }
  setFocus(component: any): void { this.focusedComponent = component; }
}
