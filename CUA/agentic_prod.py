import os
import sys
import time
import socket
from pathlib import Path
from queue import Queue
from playwright.sync_api import sync_playwright
from google import genai
from google.genai import types


# --- COMMAND SOURCES ---
class TerminalCommandSource:
    """Command source using terminal input()."""
    def get(self):
        user_request = input("\nCOMMAND: ")
        should_exit = user_request.lower().strip() in ("exit", "quit")
        return user_request, should_exit


class QueueCommandSource:
    """Command source using a queue (for message server). Blocks until command received."""
    def __init__(self, queue, exit_sentinel=None):
        self.queue = queue
        self.exit_sentinel = exit_sentinel

    def get(self):
        item = self.queue.get()
        if item is self.exit_sentinel:
            return "", True
        return item, False

# --- 1. SETUP ---
GEMINI_API_KEY = "YOUR_GEMINI_API_KEY"

# Platform-specific Chrome user data path
if sys.platform == "darwin":  # macOS
    CHROME_USER_DATA = str(Path(__file__).parent / "chrome_profile")
else:  # Windows
    CHROME_USER_DATA = r"C:\Users\User\Desktop\MND agent\automation_proxy"

client = genai.Client(api_key=GEMINI_API_KEY)

# Network fix for Windows (IPv4 preference) - typically not needed on macOS
if sys.platform == "win32":
    _old_getaddrinfo = socket.getaddrinfo
    def new_getaddrinfo(*args, **kwargs):
        responses = _old_getaddrinfo(*args, **kwargs)
        return [r for r in responses if r[0] == socket.AF_INET]
    socket.getaddrinfo = new_getaddrinfo

# --- 2. TOOLS ---
def denormalize(val, total):
    """Convert normalized coordinate (0-999) to pixel value."""
    return int(val / 1000 * total)

def _get_viewport(page):
    """Get current viewport dimensions for coordinate denormalization."""
    w = page.evaluate("window.innerWidth")
    h = page.evaluate("window.innerHeight")
    return w, h

def _press_key_combo(keys_str):
    """Convert key combo (e.g. 'Control+C', 'Enter') to Playwright format."""
    if not keys_str:
        return None
    keys_str = keys_str.strip()
    parts = [p.strip() for p in keys_str.split("+")]
    # Single key (Enter, Backspace, etc.) - pass through
    if len(parts) == 1:
        return keys_str
    # Modifier+key: Playwright wants "Control+c" (lowercase letter)
    mod_map = {"control": "Control", "ctrl": "Control", "meta": "Meta", "command": "Meta", "alt": "Alt", "shift": "Shift"}
    mods = []
    key = ""
    for p in parts:
        low = p.lower()
        if low in mod_map:
            mods.append(mod_map[low])
        else:
            key = p.lower() if len(p) == 1 else p
    return "+".join(mods + [key]) if key else keys_str

def execute_action(call, context, page, on_update=None):
    fname = call.name
    args = call.args or {}
    emit = on_update if on_update else (lambda m: print(m))
    emit(f"  -> Action: {fname}")
    
    try:
        # --- No-arg actions ---
        if fname == "open_web_browser":
            # Browser already open
            pass
        
        elif fname == "wait_5_seconds":
            time.sleep(5)
        
        elif fname == "go_back":
            page.go_back(timeout=10000)
        
        elif fname == "go_forward":
            page.go_forward(timeout=10000)
        
        elif fname == "search":
            page.goto("https://www.google.com", timeout=30000)
        
        # --- Navigation ---
        elif fname == "navigate":
            url = args.get("url", "")
            if not url.startswith("http"):
                url = f"https://{url}"
            if page.url != "about:blank" and "google.com/search" not in page.url:
                page = context.new_page()
            page.goto(url, timeout=30000)
        
        elif fname == "switch_tab":
            idx = int(args.get("index", 0))
            if 0 <= idx < len(context.pages):
                page = context.pages[idx]
                page.bring_to_front()
        
        # --- Click & Hover ---
        elif fname == "click_at":
            w, h = _get_viewport(page)
            x = denormalize(args.get("x", 500), w)
            y = denormalize(args.get("y", 500), h)
            page.mouse.click(x, y)
            time.sleep(0.5)
        
        elif fname == "hover_at":
            w, h = _get_viewport(page)
            x = denormalize(args.get("x", 500), w)
            y = denormalize(args.get("y", 500), h)
            page.mouse.move(x, y)
            time.sleep(0.3)
        
        # --- Typing ---
        elif fname == "type_text_at":
            w, h = _get_viewport(page)
            x = denormalize(args.get("x", 500), w)
            y = denormalize(args.get("y", 500), h)
            text = args.get("text", "")
            press_enter = args.get("press_enter", True)
            clear_before = args.get("clear_before_typing", True)
            
            page.mouse.click(x, y)
            time.sleep(0.2)
            if clear_before:
                # Mac: Command+A, Windows: Control+A
                sel_all = "Meta+A" if sys.platform == "darwin" else "Control+A"
                page.keyboard.press(sel_all)
                page.keyboard.press("Backspace")
            page.keyboard.type(text, delay=50)
            if press_enter:
                time.sleep(0.2)
                page.keyboard.press("Enter")
        
        elif fname == "type_text":
            # Legacy: type into focused area (no coordinates)
            page.keyboard.type(args.get("text", ""), delay=50)
            if args.get("press_enter"):
                time.sleep(0.2)
                page.keyboard.press("Enter")
        
        # --- Keyboard ---
        elif fname == "key_combination":
            keys = args.get("keys", "")
            combo = _press_key_combo(keys)
            if combo:
                page.keyboard.press(combo)
            else:
                raise ValueError("key_combination requires 'keys' parameter")
        
        # --- Scrolling ---
        elif fname == "scroll_document":
            direction = (args.get("direction") or "down").lower()
            delta = 400
            dx, dy = 0, 0
            if direction == "down":
                dy = delta
            elif direction == "up":
                dy = -delta
            elif direction == "right":
                dx = delta
            elif direction == "left":
                dx = -delta
            page.mouse.wheel(dx, dy)
            time.sleep(0.5)
        
        elif fname == "scroll_at":
            w, h = _get_viewport(page)
            x = denormalize(args.get("x", 500), w)
            y = denormalize(args.get("y", 500), h)
            direction = (args.get("direction") or "down").lower()
            magnitude = args.get("magnitude", 800)
            delta = int(magnitude / 1000 * 400)  # Scale to scroll amount
            dx, dy = 0, 0
            if direction == "down":
                dy = delta
            elif direction == "up":
                dy = -delta
            elif direction == "right":
                dx = delta
            elif direction == "left":
                dx = -delta
            page.mouse.move(x, y)
            page.mouse.wheel(dx, dy)
            time.sleep(0.5)
        
        # --- Drag and drop ---
        elif fname == "drag_and_drop":
            w, h = _get_viewport(page)
            x1 = denormalize(args.get("x", 0), w)
            y1 = denormalize(args.get("y", 0), h)
            x2 = denormalize(args.get("destination_x", 500), w)
            y2 = denormalize(args.get("destination_y", 500), h)
            page.mouse.move(x1, y1)
            page.mouse.down()
            page.mouse.move(x2, y2)
            page.mouse.up()
            time.sleep(0.5)
        
        else:
            print(f"     [Warning]: Unknown action '{fname}'")
            return page, f"Unknown action: {fname}"
        
        # Wait for potential page updates
        try:
            page.wait_for_load_state(timeout=5000)
        except Exception:
            pass
        time.sleep(0.5)
        return page, "success"
        
    except Exception as e:
        print(f"     [Error]: {e}")
        return page, str(e)

# --- 3. AGENT TOOLS CONFIG ---
CUA_TOOLS = [
    {"name": "open_web_browser", "description": "Opens the web browser. Use when browser needs to be opened.", "parameters": {"type": "OBJECT", "properties": {}}},
    {"name": "wait_5_seconds", "description": "Pauses 5 seconds for dynamic content or animations to load.", "parameters": {"type": "OBJECT", "properties": {}}},
    {"name": "go_back", "description": "Navigate to the previous page in browser history.", "parameters": {"type": "OBJECT", "properties": {}}},
    {"name": "go_forward", "description": "Navigate to the next page in browser history.", "parameters": {"type": "OBJECT", "properties": {}}},
    {"name": "search", "description": "Go to the default search engine homepage (e.g. Google).", "parameters": {"type": "OBJECT", "properties": {}}},
    {"name": "navigate", "description": "Navigate the browser to a URL.", "parameters": {"type": "OBJECT", "properties": {"url": {"type": "STRING"}}}},
    {"name": "switch_tab", "description": "Switch to tab by index (0-based).", "parameters": {"type": "OBJECT", "properties": {"index": {"type": "INTEGER"}}}},
    {"name": "click_at", "description": "Click at coordinate (x,y). Coordinates are 0-999 normalized.", "parameters": {"type": "OBJECT", "properties": {"x": {"type": "INTEGER"}, "y": {"type": "INTEGER"}}}},
    {"name": "hover_at", "description": "Hover mouse at coordinate. Useful for sub-menus.", "parameters": {"type": "OBJECT", "properties": {"x": {"type": "INTEGER"}, "y": {"type": "INTEGER"}}}},
    {"name": "type_text_at", "description": "Type text at coordinate. Clicks first, optionally clears and presses Enter.", "parameters": {"type": "OBJECT", "properties": {"x": {"type": "INTEGER"}, "y": {"type": "INTEGER"}, "text": {"type": "STRING"}, "press_enter": {"type": "BOOLEAN"}, "clear_before_typing": {"type": "BOOLEAN"}}}},
    {"name": "type_text", "description": "Type text into currently focused element.", "parameters": {"type": "OBJECT", "properties": {"text": {"type": "STRING"}, "press_enter": {"type": "BOOLEAN"}}}},
    {"name": "key_combination", "description": "Press keys or combos (e.g. Control+C, Enter).", "parameters": {"type": "OBJECT", "properties": {"keys": {"type": "STRING"}}}},
    {"name": "scroll_document", "description": "Scroll the webpage up, down, left, or right.", "parameters": {"type": "OBJECT", "properties": {"direction": {"type": "STRING", "enum": ["up", "down", "left", "right"]}}}},
    {"name": "scroll_at", "description": "Scroll at coordinate (x,y) in a direction.", "parameters": {"type": "OBJECT", "properties": {"x": {"type": "INTEGER"}, "y": {"type": "INTEGER"}, "direction": {"type": "STRING"}, "magnitude": {"type": "INTEGER"}}}},
    {"name": "drag_and_drop", "description": "Drag from (x,y) to (destination_x, destination_y).", "parameters": {"type": "OBJECT", "properties": {"x": {"type": "INTEGER"}, "y": {"type": "INTEGER"}, "destination_x": {"type": "INTEGER"}, "destination_y": {"type": "INTEGER"}}}}
]


# --- 4. MAIN LOOP ---
def run_agent(command_source=None, on_update=None):
    """
    Run the CUA agent loop.
    command_source: object with get() -> (command: str, should_exit: bool). Default: TerminalCommandSource().
    on_update: callback(message: str) for status updates. Default: print.
    """
    if command_source is None:
        command_source = TerminalCommandSource()
    if on_update is None:
        on_update = lambda msg: print(msg)

    with sync_playwright() as p:
        on_update("Launching Stable Agent with Smart-Typing...")
        context = p.chromium.launch_persistent_context(
            user_data_dir=CHROME_USER_DATA, headless=False, channel="chrome",
            args=['--start-maximized', '--disable-blink-features=AutomationControlled'],
            no_viewport=True
        )

        page = context.pages[0]
        if page.url == "about:blank":
            page.goto("https://www.google.com")

        config = types.GenerateContentConfig(tools=[{"function_declarations": CUA_TOOLS}])

        while True:
            on_update("\n[ACTIVE TABS]")
            for i, p_tab in enumerate(context.pages):
                on_update(f"Index {i}: {p_tab.url}")

            user_request, should_exit = command_source.get()
            if should_exit:
                break

            page = context.pages[-1]
            shot = page.screenshot(type="jpeg", quality=30)

            task_text = (f"Task: {user_request}. Tabs: {len(context.pages)}. "
                        "Use coordinates on a 1000x1000 grid (x,y from 0-999). "
                        "Use type_text_at to click and type. Use scroll_document or scroll_at to see more. "
                        "Keep taking actions until the task is COMPLETE. Only stop when done.")
            contents = [
                types.Content(role="user", parts=[
                    types.Part.from_text(text=task_text),
                    types.Part.from_bytes(data=shot, mime_type='image/jpeg')
                ])
            ]

            turn_limit = 15
            for turn in range(turn_limit):
                try:
                    on_update(f"\n--- Turn {turn + 1} ---")
                    response = client.models.generate_content(
                        model='gemini-3-flash-preview',
                        contents=contents,
                        config=config,
                    )
                    candidate = response.candidates[0]
                    contents.append(candidate.content)

                    for part in candidate.content.parts:
                        if part.text:
                            on_update(f"[AGENT]: {part.text}")

                    function_calls = [p.function_call for p in candidate.content.parts if p.function_call]
                    if not function_calls:
                        on_update("Task complete.")
                        break

                    results = []
                    for call in function_calls:
                        page, status = execute_action(call, context, page, on_update=on_update)
                        results.append((call.name, {"status": status, "url": page.url}))

                    shot = page.screenshot(type="jpeg", quality=30)
                    response_parts = []
                    for name, result in results:
                        response_parts.append(types.Part.from_function_response(
                            name=name,
                            response=result,
                            parts=[types.FunctionResponsePart.from_bytes(data=shot, mime_type="image/jpeg")]
                        ))
                    contents.append(types.Content(role="user", parts=response_parts))

                except Exception as e:
                    on_update(f"Error: {e}")
                    break

        context.close()


if __name__ == "__main__":
    run_agent()
