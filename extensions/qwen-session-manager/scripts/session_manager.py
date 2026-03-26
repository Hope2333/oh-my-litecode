#!/usr/bin/env python3
"""
Qwen Session Manager - TUI Interface
Manage Qwen sessions with a curses-based terminal UI
"""

import curses
import json
import os
import sys
import glob
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional, Any


class SessionManager:
    """Manage Qwen sessions"""
    
    def __init__(self, sessions_dir: str):
        self.sessions_dir = Path(sessions_dir)
        self.sessions_dir.mkdir(parents=True, exist_ok=True)
        self.sessions: List[Dict[str, Any]] = []
        self.selected_index = 0
        self.scroll_offset = 0
        self.message = ""
        self.message_time = 0
        self.refresh_sessions()
    
    def refresh_sessions(self):
        """Load all sessions from disk"""
        self.sessions = []
        for session_file in self.sessions_dir.glob('*.json'):
            try:
                with open(session_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                self.sessions.append({
                    'session_id': data.get('session_id', ''),
                    'name': data.get('name', ''),
                    'status': data.get('status', 'inactive'),
                    'created_at': data.get('created_at', ''),
                    'updated_at': data.get('updated_at', ''),
                    'message_count': len(data.get('messages', [])),
                    'file': str(session_file),
                    'data': data
                })
            except Exception as e:
                pass
        
        # Sort by updated_at descending
        self.sessions.sort(key=lambda x: x.get('updated_at', ''), reverse=True)
    
    def delete_session(self, index: int) -> bool:
        """Delete a session by index"""
        if 0 <= index < len(self.sessions):
            session = self.sessions[index]
            try:
                os.remove(session['file'])
                self.refresh_sessions()
                if self.selected_index >= len(self.sessions):
                    self.selected_index = max(0, len(self.sessions) - 1)
                return True
            except Exception as e:
                return False
        return False
    
    def delete_selected(self, indices: List[int]) -> int:
        """Delete multiple sessions by indices, returns count of deleted"""
        deleted = 0
        for idx in sorted(indices, reverse=True):
            if self.delete_session(idx):
                deleted += 1
        return deleted
    
    def get_session_details(self, index: int) -> Optional[Dict[str, Any]]:
        """Get full session details"""
        if 0 <= index < len(self.sessions):
            return self.sessions[index]
        return None
    
    def clear_all(self) -> int:
        """Clear all sessions, returns count"""
        count = 0
        for session in self.sessions[:]:
            try:
                os.remove(session['file'])
                count += 1
            except:
                pass
        self.refresh_sessions()
        return count


class SessionTUI:
    """Curses-based TUI for session management"""
    
    def __init__(self, manager: SessionManager):
        self.manager = manager
        self.running = True
        self.mode = 'normal'  # normal, confirm_delete, multi_select, details
        self.delete_indices: List[int] = []
        self.show_help = False
    
    def run(self, stdscr):
        """Main TUI loop"""
        curses.curs_set(0)
        stdscr.timeout(100)
        
        # Initialize colors
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Selected
        curses.init_pair(2, curses.COLOR_CYAN, -1)  # Header
        curses.init_pair(3, curses.COLOR_YELLOW, -1)  # Warning
        curses.init_pair(4, curses.COLOR_GREEN, -1)  # Success
        curses.init_pair(5, curses.COLOR_RED, -1)  # Error
        curses.init_pair(6, curses.COLOR_MAGENTA, -1)  # Status
        curses.init_pair(7, curses.COLOR_WHITE, curses.COLOR_RED)  # Delete highlight
        
        while self.running:
            stdscr.clear()
            self.draw(stdscr)
            stdscr.refresh()
            
            try:
                key = stdscr.getch()
                if key != -1:
                    self.handle_input(stdscr, key)
            except KeyboardInterrupt:
                self.running = False
    
    def draw(self, stdscr):
        """Draw the interface"""
        height, width = stdscr.getmaxyx()
        
        # Title
        title = " Qwen Session Manager "
        stdscr.attron(curses.color_pair(2) | curses.A_BOLD)
        stdscr.addstr(0, (width - len(title)) // 2, title[:width-1])
        stdscr.attroff(curses.color_pair(2) | curses.A_BOLD)
        
        # Help line
        help_text = "↑↓:Navigate | Enter:Details | d:Delete | m:Multi | r:Refresh | q:Quit | ?:Help"
        stdscr.addstr(1, 2, help_text[:width-3], curses.color_pair(6))
        
        # Session list header
        header = f"{'ID':<36} {'Name':<20} {'Status':<10} {'Msgs':<6} {'Updated':<19}"
        stdscr.addstr(3, 2, header[:width-3], curses.A_UNDERLINE)
        
        # Session list
        start = self.manager.scroll_offset
        visible_rows = height - 7
        
        for i, session in enumerate(self.manager.sessions[start:start + visible_rows]):
            row = i + 4
            if row >= height - 3:
                break
            
            session_id = session['session_id'][:34] + '..' if len(session['session_id']) > 36 else session['session_id']
            name = (session['name'] or 'unnamed')[:18]
            status = session['status'][:8]
            msg_count = str(session['message_count'])
            updated = session['updated_at'][:19] if session['updated_at'] else 'N/A'
            
            line = f"{session_id:<36} {name:<20} {status:<10} {msg_count:<6} {updated:<19}"
            
            actual_idx = start + i
            is_selected = actual_idx == self.manager.selected_index
            is_multi_delete = actual_idx in self.delete_indices
            
            if is_multi_delete:
                stdscr.addstr(row, 2, line[:width-3], curses.color_pair(7))
            elif is_selected:
                stdscr.addstr(row, 2, line[:width-3], curses.color_pair(1))
            else:
                stdscr.addstr(row, 2, line[:width-3])
        
        # Status bar
        status_text = f" Sessions: {len(self.manager.sessions)} | Selected: {self.manager.selected_index + 1}/{len(self.manager.sessions)} "
        if self.mode == 'multi_select':
            status_text += f"| Marked for delete: {len(self.delete_indices)} "
        stdscr.addstr(height - 2, 0, status_text[:width-1], curses.color_pair(6))
        
        # Message
        if self.manager.message:
            stdscr.addstr(height - 1, 2, self.manager.message[:width-3], curses.color_pair(4))
        
        # Mode-specific overlays
        if self.mode == 'confirm_delete':
            self.draw_confirm_dialog(stdscr, height, width)
        elif self.mode == 'details':
            self.draw_details(stdscr, height, width)
        elif self.show_help:
            self.draw_help(stdscr, height, width)
    
    def draw_confirm_dialog(self, stdscr, height, width):
        """Draw delete confirmation dialog"""
        dialog_w = 50
        dialog_h = 7
        start_y = (height - dialog_h) // 2
        start_x = (width - dialog_w) // 2
        
        # Draw box
        for y in range(dialog_h):
            for x in range(dialog_w):
                if y == 0 or y == dialog_h - 1:
                    stdscr.addch(start_y + y, start_x + x, '─')
                elif x == 0 or x == dialog_w - 1:
                    stdscr.addch(start_y + y, start_x + x, '│')
        
        # Corners
        stdscr.addch(start_y, start_x, '┌')
        stdscr.addch(start_y, start_x + dialog_w - 1, '┐')
        stdscr.addch(start_y + dialog_h - 1, start_x, '└')
        stdscr.addch(start_y + dialog_h - 1, start_x + dialog_w - 1, '┘')
        
        title = " Confirm Delete "
        stdscr.addstr(start_y, start_x + (dialog_w - len(title)) // 2, title, curses.A_BOLD)
        
        msg = "Delete this session?"
        stdscr.addstr(start_y + 2, start_x + (dialog_w - len(msg)) // 2, msg)
        
        options = "[Y]es  [N]o"
        stdscr.addstr(start_y + 4, start_x + (dialog_w - len(options)) // 2, options, curses.color_pair(3))
    
    def draw_details(self, stdscr, height, width):
        """Draw session details view"""
        session = self.manager.get_session_details(self.manager.selected_index)
        if not session:
            return
        
        dialog_w = min(80, width - 4)
        dialog_h = min(30, height - 4)
        start_y = (height - dialog_h) // 2
        start_x = (width - dialog_w) // 2
        
        # Draw box
        stdscr.attron(curses.color_pair(2))
        for y in range(dialog_h):
            stdscr.addstr(start_y + y, start_x, '│')
            stdscr.addstr(start_y + y, start_x + dialog_w - 1, '│')
        for x in range(dialog_w):
            stdscr.addstr(start_y, start_x + x, '─')
            stdscr.addstr(start_y + dialog_h - 1, start_x + x, '─')
        stdscr.attroff(curses.color_pair(2))
        
        # Corners
        stdscr.addch(start_y, start_x, '┌')
        stdscr.addch(start_y, start_x + dialog_w - 1, '┐')
        stdscr.addch(start_y + dialog_h - 1, start_x, '└')
        stdscr.addch(start_y + dialog_h - 1, start_x + dialog_w - 1, '┘')
        
        # Title
        title = f" Session: {session['name'] or 'unnamed'} "
        stdscr.addstr(start_y, start_x + (dialog_w - len(title)) // 2, title, curses.A_BOLD)
        
        # Details
        details = [
            f"ID: {session['session_id']}",
            f"Status: {session['status']}",
            f"Created: {session['created_at']}",
            f"Updated: {session['updated_at']}",
            f"Messages: {session['message_count']}",
            "",
            "Recent Messages:",
        ]
        
        messages = session['data'].get('messages', [])[-10:]
        for msg in messages:
            role = msg.get('role', 'unknown')[:10]
            content = msg.get('content', '')[:60]
            details.append(f"  [{role}] {content}...")
        
        for i, line in enumerate(details[:dialog_h - 4]):
            if start_y + 2 + i < start_y + dialog_h - 2:
                stdscr.addstr(start_y + 2 + i, start_x + 2, line[:dialog_w - 4])
        
        # Footer
        footer = "Press any key to close"
        stdscr.addstr(start_y + dialog_h - 2, start_x + (dialog_w - len(footer)) // 2, footer, curses.color_pair(6))
    
    def draw_help(self, stdscr, height, width):
        """Draw help screen"""
        dialog_w = 60
        dialog_h = 20
        start_y = (height - dialog_h) // 2
        start_x = (width - dialog_w) // 2
        
        # Draw box
        stdscr.attron(curses.color_pair(2))
        for y in range(dialog_h):
            stdscr.addstr(start_y + y, start_x, '│')
            stdscr.addstr(start_y + y, start_x + dialog_w - 1, '│')
        for x in range(dialog_w):
            stdscr.addstr(start_y, start_x + x, '─')
            stdscr.addstr(start_y + dialog_h - 1, start_x + x, '─')
        stdscr.attroff(curses.color_pair(2))
        
        # Corners
        stdscr.addch(start_y, start_x, '┌')
        stdscr.addch(start_y, start_x + dialog_w - 1, '┐')
        stdscr.addch(start_y + dialog_h - 1, start_x, '└')
        stdscr.addch(start_y + dialog_h - 1, start_x + dialog_w - 1, '┘')
        
        title = " Help "
        stdscr.addstr(start_y, start_x + (dialog_w - len(title)) // 2, title, curses.A_BOLD)
        
        help_lines = [
            "Navigation:",
            "  ↑/k  Move up",
            "  ↓/j  Move down",
            "",
            "Actions:",
            "  Enter  View session details",
            "  d      Delete session",
            "  m      Toggle multi-select mode",
            "  x      Mark/unmark in multi-select",
            "  D      Execute multi-delete",
            "  r      Refresh list",
            "  C      Clear all sessions",
            "",
            "Other:",
            "  ?      Toggle this help",
            "  q      Quit",
            "",
            "Press ? to close help"
        ]
        
        for i, line in enumerate(help_lines):
            stdscr.addstr(start_y + 2 + i, start_x + 2, line[:dialog_w - 4])
    
    def handle_input(self, stdscr, key):
        """Handle keyboard input"""
        if self.show_help:
            if key in [ord('?'), ord('q'), 27]:  # ? or q or ESC
                self.show_help = False
            return
        
        if self.mode == 'details':
            self.mode = 'normal'
            return
        
        if self.mode == 'confirm_delete':
            if key in [ord('y'), ord('Y')]:
                if self.manager.delete_session(self.manager.selected_index):
                    self.manager.message = "Session deleted"
                else:
                    self.manager.message = "Failed to delete session"
            elif key in [ord('n'), ord('N'), 27]:
                pass
            self.mode = 'normal'
            return
        
        if key in [curses.KEY_UP, ord('k')]:
            if self.manager.selected_index > 0:
                self.manager.selected_index -= 1
                if self.manager.selected_index < self.manager.scroll_offset:
                    self.manager.scroll_offset = self.manager.selected_index
        
        elif key in [curses.KEY_DOWN, ord('j')]:
            if self.manager.selected_index < len(self.manager.sessions) - 1:
                self.manager.selected_index += 1
                visible = stdscr.getmaxyx()[0] - 7
                if self.manager.selected_index >= self.manager.scroll_offset + visible:
                    self.manager.scroll_offset = self.manager.selected_index - visible + 1
        
        elif key in [10, 13]:  # Enter
            if self.manager.sessions:
                self.mode = 'details'
        
        elif key == ord('d'):
            if self.manager.sessions:
                self.mode = 'confirm_delete'
        
        elif key == ord('m'):
            if self.mode == 'multi_select':
                self.mode = 'normal'
                self.delete_indices = []
                self.manager.message = "Multi-select mode disabled"
            else:
                self.mode = 'multi_select'
                self.manager.message = "Multi-select mode enabled - use x to mark"
        
        elif key == ord('x') and self.mode == 'multi_select':
            if self.manager.selected_index in self.delete_indices:
                self.delete_indices.remove(self.manager.selected_index)
            else:
                self.delete_indices.append(self.manager.selected_index)
        
        elif key == ord('D') and self.mode == 'multi_select' and self.delete_indices:
            # Confirm multi-delete
            self.mode = 'confirm_delete'
        
        elif key == ord('r'):
            self.manager.refresh_sessions()
            self.manager.message = "Sessions refreshed"
        
        elif key == ord('C'):
            # Clear all confirmation
            if len(self.manager.sessions) > 0:
                self.manager.message = f"Cleared {self.manager.clear_all()} sessions"
        
        elif key == ord('?'):
            self.show_help = True
        
        elif key in [ord('q'), 27]:  # q or ESC
            self.running = False


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Qwen Session Manager TUI')
    parser.add_argument('--sessions-dir', '-d', 
                        default=os.path.expanduser('~/.local/home/qwen/.qwen/sessions'),
                        help='Sessions directory')
    parser.add_argument('--list', '-l', action='store_true',
                        help='List sessions (non-interactive)')
    parser.add_argument('--delete', '-D', metavar='SESSION_ID',
                        help='Delete a specific session')
    parser.add_argument('--clear-all', '-c', action='store_true',
                        help='Clear all sessions')
    parser.add_argument('--json', '-j', action='store_true',
                        help='Output in JSON format')
    
    args = parser.parse_args()
    
    manager = SessionManager(args.sessions_dir)
    
    # Non-interactive modes
    if args.list:
        if args.json:
            print(json.dumps({'sessions': manager.sessions, 'total': len(manager.sessions)}, indent=2))
        else:
            if not manager.sessions:
                print("No sessions found")
            else:
                print(f"{'SESSION_ID':<40} {'NAME':<20} {'STATUS':<10} {'MSGS':<6} {'UPDATED'}")
                print("=" * 95)
                for s in manager.sessions:
                    name = (s['name'] or 'unnamed')[:18]
                    print(f"{s['session_id']:<40} {name:<20} {s['status']:<10} {s['message_count']:<6} {s['updated_at'][:19] if s['updated_at'] else 'N/A'}")
                print(f"\nTotal: {len(manager.sessions)} sessions")
        return
    
    if args.delete:
        deleted = False
        for i, s in enumerate(manager.sessions):
            if s['session_id'] == args.delete or s['session_id'].startswith(args.delete):
                if manager.delete_session(i):
                    print(f"Deleted session: {args.delete}")
                    deleted = True
                    break
        if not deleted:
            print(f"Session not found: {args.delete}", file=sys.stderr)
            sys.exit(1)
        return
    
    if args.clear_all:
        count = manager.clear_all()
        print(f"Cleared {count} sessions")
        return
    
    # Interactive TUI
    try:
        app = SessionTUI(manager)
        curses.wrapper(app.run)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
