/**
 * Terminal Renderer - OML Modules
 * 
 * ANSI escape code based terminal rendering.
 */

import * as readline from 'readline';
import type { TextStyle, Size, BoxOptions, ButtonOptions, InputOptions, ListOptions, MenuOptions } from './types.js';

export class TerminalRenderer {
  private width: number = 80;
  private height: number = 24;
  private buffer: string[] = [];
  private cursorVisible: boolean = true;
  private rl: readline.Interface | null = null;

  constructor() {
    this.updateSize();
    this.initBuffer();
  }

  private initBuffer(): void {
    this.buffer = Array(this.height).fill('').map(() => ' '.repeat(this.width));
  }

  private updateSize(): void {
    if (process.stdout.isTTY) {
      this.width = process.stdout.columns || 80;
      this.height = process.stdout.rows || 24;
    }
  }

  // ========== ANSI Escape Codes ==========

  hideCursor(): string {
    return '\x1b[?25l';
  }

  showCursor(): string {
    return '\x1b[?25h';
  }

  moveCursor(row: number, col: number): string {
    return `\x1b[${row};${col}H`;
  }

  clearScreen(): string {
    return '\x1b[2J\x1b[H';
  }

  clearLine(): string {
    return '\x1b[2K';
  }

  // ========== Colors and Styles ==========

  private colorCode(color: string, isBg: boolean): string {
    const colors: Record<string, number> = {
      black: 30, red: 31, green: 32, yellow: 33,
      blue: 34, magenta: 35, cyan: 36, white: 37,
    };
    const base = isBg ? 40 : 30;
    return `\x1b[${colors[color] || base}m`;
  }

  private styleCode(style: string): string {
    const styles: Record<string, number> = {
      normal: 0, bold: 1, dim: 2, underline: 4,
      blink: 5, reverse: 7, hidden: 8,
    };
    return `\x1b[${styles[style] || 0}m`;
  }

  applyStyle(textStyle?: TextStyle): string {
    if (!textStyle) return '';
    let codes = '';
    if (textStyle.style) codes += this.styleCode(textStyle.style);
    if (textStyle.fg) codes += this.colorCode(textStyle.fg, false);
    if (textStyle.bg) codes += this.colorCode(textStyle.bg, true);
    return codes;
  }

  resetStyle(): string {
    return '\x1b[0m';
  }

  // ========== Drawing Functions ==========

  drawText(text: string, x: number, y: number, style?: TextStyle): void {
    if (y < 0 || y >= this.height) return;
    const codes = style ? this.applyStyle(style) : '';
    const reset = style ? this.resetStyle() : '';
    const line = this.buffer[y];
    const paddedText = codes + text + reset;
    this.buffer[y] = line.substring(0, x) + paddedText + line.substring(x + text.length + (codes ? 9 : 0));
  }

  drawBox(x: number, y: number, w: number, h: number, title?: string): void {
    const corners = { tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│' };
    
    // Draw corners
    this.drawText(corners.tl, x, y);
    this.drawText(corners.tr, x + w - 1, y);
    this.drawText(corners.bl, x, y + h - 1);
    this.drawText(corners.br, x + w - 1, y + h - 1);
    
    // Draw horizontal lines
    for (let i = 1; i < w - 1; i++) {
      this.drawText(corners.h, x + i, y);
      this.drawText(corners.h, x + i, y + h - 1);
    }
    
    // Draw vertical lines
    for (let i = 1; i < h - 1; i++) {
      this.drawText(corners.v, x, y + i);
      this.drawText(corners.v, x + w - 1, y + i);
    }
    
    // Draw title
    if (title) {
      this.drawText(` ${title} `, x + 2, y);
    }
  }

  drawButton(label: string, x: number, y: number, width: number, selected: boolean): void {
    const style: TextStyle = selected ? { fg: 'black', bg: 'white', style: 'bold' } : { fg: 'cyan' };
    const padding = width - label.length;
    const leftPad = Math.floor(padding / 2);
    const rightPad = padding - leftPad;
    const btnText = '[' + ' '.repeat(leftPad) + label + ' '.repeat(rightPad) + ']';
    this.drawText(btnText, x, y, style);
  }

  drawInput(label: string | undefined, x: number, y: number, width: number, value: string, password: boolean): void {
    if (label) {
      this.drawText(label, x, y);
      x += label.length + 1;
      width -= label.length + 1;
    }
    const displayValue = password ? '•'.repeat(value.length) : value;
    this.drawText(displayValue + ' '.repeat(width - displayValue.length), x, y, { fg: 'yellow' });
  }

  drawList(x: number, y: number, w: number, h: number, items: Array<{ label: string; selected?: boolean }>, selectedIndex: number): void {
    for (let i = 0; i < Math.min(h, items.length); i++) {
      const item = items[i];
      const marker = i === selectedIndex ? '▶ ' : '  ';
      const style: TextStyle = item.selected ? { fg: 'black', bg: 'white' } : i === selectedIndex ? { fg: 'green' } : {};
      const label = marker + item.label;
      this.drawText(label.substring(0, w - 2), x + 1, y + i, style);
    }
  }

  drawMenu(x: number, y: number, items: Array<{ label: string; shortcut?: string }>, title?: string): void {
    if (title) {
      this.drawText(title, x, y, { style: 'bold', fg: 'cyan' });
      y++;
    }
    const menuText = items.map(item => 
      item.shortcut ? `${item.label} [${item.shortcut}]` : item.label
    ).join(' | ');
    this.drawText(menuText, x, y, { fg: 'yellow' });
  }

  // ========== Screen Management ==========

  clear(): void {
    this.initBuffer();
    process.stdout.write(this.clearScreen());
  }

  render(): void {
    process.stdout.write(this.hideCursor());
    process.stdout.write(this.moveCursor(1, 1));
    for (const line of this.buffer) {
      process.stdout.write(line + '\n');
    }
    process.stdout.write(this.showCursor());
  }

  setSize(width: number, height: number): void {
    this.width = width;
    this.height = height;
    this.initBuffer();
  }

  getSize(): Size {
    return { width: this.width, height: this.height };
  }

  // ========== Input Handling ==========

  async readKey(): Promise<string> {
    return new Promise((resolve) => {
      if (process.stdin.isTTY) {
        process.stdin.setRawMode(true);
        process.stdin.once('data', (key) => {
          process.stdin.setRawMode(false);
          resolve(key.toString());
        });
      }
    });
  }

  async readLine(prompt: string = ''): Promise<string> {
    return new Promise((resolve) => {
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });
      rl.question(prompt, (answer) => {
        rl.close();
        resolve(answer);
      });
    });
  }

  // ========== Utility ==========

  beep(): void {
    process.stdout.write('\x07');
  }

  sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Default instance
let defaultRenderer: TerminalRenderer | null = null;

export function getDefaultRenderer(): TerminalRenderer {
  if (!defaultRenderer) {
    defaultRenderer = new TerminalRenderer();
  }
  return defaultRenderer;
}

// Convenience functions
export const drawText = (text: string, x: number, y: number, style?: TextStyle) => 
  getDefaultRenderer().drawText(text, x, y, style);
export const drawBox = (x: number, y: number, w: number, h: number, title?: string) =>
  getDefaultRenderer().drawBox(x, y, w, h, title);
export const clearScreen = () => getDefaultRenderer().clear();
export const render = () => getDefaultRenderer().render();
