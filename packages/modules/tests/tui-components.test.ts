import { describe, it, expect, beforeEach } from 'vitest';
import { TerminalRenderer } from '../src/tui/renderer.js';
import { Box, Button, Input, List, Menu, App } from '../src/tui/components.js';

describe('TUI Components', () => {
  let renderer: TerminalRenderer;

  beforeEach(() => {
    renderer = new TerminalRenderer();
    renderer.setSize(80, 24);
  });

  describe('Box', () => {
    it('should create box with single border', () => {
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10 });
      expect(() => box.render()).not.toThrow();
    });

    it('should create box with double border', () => {
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10, border: 'double' });
      expect(() => box.render()).not.toThrow();
    });

    it('should create box with rounded border', () => {
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10, border: 'rounded' });
      expect(() => box.render()).not.toThrow();
    });

    it('should create box with title', () => {
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10, title: 'Test Box' });
      expect(() => box.render()).not.toThrow();
    });

    it('should create box with no border', () => {
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10, border: 'none', title: 'Title' });
      expect(() => box.render()).not.toThrow();
    });
  });

  describe('Button', () => {
    it('should create button', () => {
      const button = new Button(renderer, { label: 'OK', x: 5, y: 5 });
      expect(() => button.render()).not.toThrow();
    });

    it('should create selected button', () => {
      const button = new Button(renderer, { label: 'OK', x: 5, y: 5, selected: true });
      expect(() => button.render()).not.toThrow();
    });

    it('should call onClick handler', () => {
      let clicked = false;
      const button = new Button(renderer, { 
        label: 'OK', 
        x: 5, 
        y: 5, 
        onClick: () => { clicked = true; } 
      });
      button.click();
      expect(clicked).toBe(true);
    });
  });

  describe('Input', () => {
    it('should create input', () => {
      const input = new Input(renderer, { x: 1, y: 1, width: 20 });
      expect(() => input.render()).not.toThrow();
    });

    it('should create input with label', () => {
      const input = new Input(renderer, { label: 'Name:', x: 1, y: 1, width: 20 });
      expect(() => input.render()).not.toThrow();
    });

    it('should create password input', () => {
      const input = new Input(renderer, { x: 1, y: 1, width: 20, password: true, value: 'secret' });
      expect(() => input.render()).not.toThrow();
    });

    it('should handle text input', () => {
      const input = new Input(renderer, { x: 1, y: 1, width: 20 });
      input.handleKey('a');
      input.handleKey('b');
      expect(input.getValue()).toBe('ab');
    });

    it('should handle backspace', () => {
      const input = new Input(renderer, { x: 1, y: 1, width: 20, value: 'abc' });
      input.handleKey('\x7f');
      expect(input.getValue()).toBe('ab');
    });

    it('should handle arrow keys', () => {
      const input = new Input(renderer, { x: 1, y: 1, width: 20, value: 'abc' });
      input.handleKey('\x1b[D'); // Left
      input.handleKey('\x1b[C'); // Right
      expect(input.getValue()).toBe('abc');
    });
  });

  describe('List', () => {
    it('should create list', () => {
      const items = [{ label: 'Item 1', value: 1 }, { label: 'Item 2', value: 2 }];
      const list = new List(renderer, { x: 1, y: 1, width: 20, height: 5, items });
      expect(() => list.render()).not.toThrow();
    });

    it('should select item', () => {
      const items = [{ label: 'Item 1', value: 1 }, { label: 'Item 2', value: 2 }];
      const list = new List(renderer, { x: 1, y: 1, width: 20, height: 5, items });
      list.select(1);
      expect(list.getSelected()?.value).toBe(2);
    });

    it('should move up', () => {
      const items = [{ label: 'Item 1', value: 1 }, { label: 'Item 2', value: 2 }, { label: 'Item 3', value: 3 }];
      const list = new List(renderer, { x: 1, y: 1, width: 20, height: 5, items, selectedIndex: 2 });
      list.moveUp();
      expect(list.getSelected()?.value).toBe(2);
    });

    it('should move down', () => {
      const items = [{ label: 'Item 1', value: 1 }, { label: 'Item 2', value: 2 }, { label: 'Item 3', value: 3 }];
      const list = new List(renderer, { x: 1, y: 1, width: 20, height: 5, items, selectedIndex: 0 });
      list.moveDown();
      expect(list.getSelected()?.value).toBe(2);
    });
  });

  describe('Menu', () => {
    it('should create menu', () => {
      const items = [{ label: 'File', shortcut: 'F' }, { label: 'Edit', shortcut: 'E' }];
      const menu = new Menu(renderer, { x: 1, y: 1, items });
      expect(() => menu.render()).not.toThrow();
    });

    it('should create menu with title', () => {
      const items = [{ label: 'File', shortcut: 'F' }];
      const menu = new Menu(renderer, { x: 1, y: 1, items, title: 'Menu' });
      expect(() => menu.render()).not.toThrow();
    });

    it('should select item', () => {
      const items = [{ label: 'File', shortcut: 'F' }, { label: 'Edit', shortcut: 'E' }];
      const menu = new Menu(renderer, { x: 1, y: 1, items });
      menu.select(1);
      expect(menu.getSelected()?.label).toBe('Edit');
    });

    it('should move left', () => {
      const items = [{ label: 'File' }, { label: 'Edit' }, { label: 'Help' }];
      const menu = new Menu(renderer, { x: 1, y: 1, items });
      menu.select(2);
      menu.moveLeft();
      expect(menu.getSelected()?.label).toBe('Edit');
    });

    it('should move right', () => {
      const items = [{ label: 'File' }, { label: 'Edit' }, { label: 'Help' }];
      const menu = new Menu(renderer, { x: 1, y: 1, items });
      menu.moveRight();
      expect(menu.getSelected()?.label).toBe('Edit');
    });

    it('should activate selected item', () => {
      let activated = false;
      const items = [{ label: 'File', action: () => { activated = true; } }];
      const menu = new Menu(renderer, { x: 1, y: 1, items });
      menu.activate();
      expect(activated).toBe(true);
    });
  });

  describe('App', () => {
    it('should create app', () => {
      const app = new App(renderer);
      expect(app).toBeDefined();
    });

    it('should add components', () => {
      const app = new App(renderer);
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10 });
      app.add(box);
      expect(app.components.length).toBe(1);
    });

    it('should render components', () => {
      const app = new App(renderer);
      const box = new Box(renderer, { x: 1, y: 1, width: 20, height: 10, title: 'Test' });
      app.add(box);
      expect(() => app.render()).not.toThrow();
    });

    it('should stop running', () => {
      const app = new App(renderer);
      app.stop();
      expect(app.running).toBe(false);
    });
  });
});
