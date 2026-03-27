import { describe, it, expect, beforeEach } from 'vitest';
import { TerminalRenderer } from '../src/tui/renderer.js';

describe('TerminalRenderer', () => {
  let renderer: TerminalRenderer;

  beforeEach(() => {
    renderer = new TerminalRenderer();
  });

  it('should initialize with default size', () => {
    const size = renderer.getSize();
    expect(size.width).toBeGreaterThan(0);
    expect(size.height).toBeGreaterThan(0);
  });

  it('should set size', () => {
    renderer.setSize(100, 30);
    const size = renderer.getSize();
    expect(size.width).toBe(100);
    expect(size.height).toBe(30);
  });

  it('should generate ANSI codes for cursor', () => {
    expect(renderer.hideCursor()).toContain('\x1b[?25l');
    expect(renderer.showCursor()).toContain('\x1b[?25h');
    expect(renderer.moveCursor(5, 10)).toContain('\x1b[5;10H');
  });

  it('should generate ANSI codes for foreground colors', () => {
    const redFg = renderer.applyStyle({ fg: 'red' });
    expect(redFg).toContain('\x1b[31m');
  });

  it('should generate ANSI codes for styles', () => {
    const bold = renderer.applyStyle({ style: 'bold' });
    expect(bold).toContain('\x1b[1m');
    
    const underline = renderer.applyStyle({ style: 'underline' });
    expect(underline).toContain('\x1b[4m');
  });

  it('should reset style', () => {
    expect(renderer.resetStyle()).toBe('\x1b[0m');
  });

  it('should clear screen', () => {
    expect(renderer.clearScreen()).toContain('\x1b[2J');
  });

  it('should draw box characters', () => {
    expect(() => renderer.drawBox(1, 1, 10, 5, 'Test')).not.toThrow();
  });

  it('should handle button drawing', () => {
    expect(() => renderer.drawButton('OK', 5, 5, 10, false)).not.toThrow();
    expect(() => renderer.drawButton('Cancel', 5, 7, 10, true)).not.toThrow();
  });

  it('should handle input drawing', () => {
    expect(() => renderer.drawInput('Name:', 1, 1, 20, 'John', false)).not.toThrow();
    expect(() => renderer.drawInput('Pass:', 1, 2, 20, 'secret', true)).not.toThrow();
  });

  it('should handle list drawing', () => {
    const items = [
      { label: 'Item 1', selected: false },
      { label: 'Item 2', selected: true },
      { label: 'Item 3', selected: false },
    ];
    expect(() => renderer.drawList(1, 1, 20, 5, items, 1)).not.toThrow();
  });

  it('should handle menu drawing', () => {
    const items = [
      { label: 'File', shortcut: 'F' },
      { label: 'Edit', shortcut: 'E' },
      { label: 'Help', shortcut: 'H' },
    ];
    expect(() => renderer.drawMenu(1, 1, items, 'Menu')).not.toThrow();
  });

  it('should beep', () => {
    expect(() => renderer.beep()).not.toThrow();
  });

  it('should sleep', async () => {
    const start = Date.now();
    await renderer.sleep(10);
    const elapsed = Date.now() - start;
    expect(elapsed).toBeGreaterThanOrEqual(10);
  });
});
