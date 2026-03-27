/**
 * TUI Types - OML Modules
 */

export type Color = 'black' | 'red' | 'green' | 'yellow' | 'blue' | 'magenta' | 'cyan' | 'white';

export type Style = 'normal' | 'bold' | 'dim' | 'underline' | 'blink' | 'reverse' | 'hidden';

export interface TextStyle {
  fg?: Color;
  bg?: Color;
  style?: Style;
}

export interface Position {
  row: number;
  col: number;
}

export interface Size {
  width: number;
  height: number;
}

export interface BoxOptions {
  x: number;
  y: number;
  width: number;
  height: number;
  title?: string;
  border?: 'single' | 'double' | 'rounded' | 'none';
  style?: TextStyle;
}

export interface ButtonOptions {
  label: string;
  x: number;
  y: number;
  width?: number;
  selected?: boolean;
  onClick?: () => void;
}

export interface InputOptions {
  label?: string;
  x: number;
  y: number;
  width: number;
  value?: string;
  password?: boolean;
  placeholder?: string;
}

export interface ListItem {
  label: string;
  value: any;
  selected?: boolean;
}

export interface ListOptions {
  x: number;
  y: number;
  width: number;
  height: number;
  items: ListItem[];
  selectedIndex?: number;
}

export interface MenuOptions {
  x: number;
  y: number;
  items: Array<{ label: string; shortcut?: string; action?: () => void }>;
  title?: string;
}

export interface Screen {
  clear(): void;
  render(): void;
  addBox(options: BoxOptions): void;
  addButton(options: ButtonOptions): void;
  addInput(options: InputOptions): void;
  addList(options: ListOptions): void;
  addMenu(options: MenuOptions): void;
  drawText(text: string, x: number, y: number, style?: TextStyle): void;
  drawBox(x: number, y: number, w: number, h: number, title?: string): void;
  moveCursor(row: number, col: number): void;
  hideCursor(): void;
  showCursor(): void;
  setSize(width: number, height: number): void;
  getSize(): Size;
}
