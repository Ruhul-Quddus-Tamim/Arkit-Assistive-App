"""
Message server for iPhone → CUA Agent integration.
Exposes a WebSocket endpoint; commands from clients are queued and processed by the agent.
"""
import asyncio
import json
import threading
from queue import Queue

from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

# Import agent components (must be after playwright/genai imports are ready)
from agentic_prod import (
    run_agent,
    QueueCommandSource,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start agent thread on startup."""
    global event_loop, agent_thread
    event_loop = asyncio.get_running_loop()
    agent_thread = threading.Thread(target=_run_agent_loop, daemon=True)
    agent_thread.start()
    yield
    # Shutdown: could put EXIT_SENTINEL in queue if we want graceful exit


app = FastAPI(title="CUA Agent Message Server", lifespan=lifespan)

# Shared state
command_queue: Queue = Queue()
clients: set[WebSocket] = set()
clients_lock = threading.Lock()
event_loop: asyncio.AbstractEventLoop | None = None
agent_thread: threading.Thread | None = None
EXIT_SENTINEL = object()


def _should_send_to_ios(msg: str) -> bool:
    """Only send Turn N, [AGENT]:, and Task complete. to iOS - skip actions, tabs, etc."""
    s = msg.strip()
    if s.startswith("--- Turn ") and s.endswith("---"):
        return True
    if "[AGENT]:" in msg:
        return True
    if s == "Task complete.":
        return True
    return False


def _infer_message_type(msg: str) -> str:
    """Infer JSON type from message content for client display."""
    if msg.strip().startswith("[AGENT]:"):
        return "agent"
    if "Task complete." in msg or msg.strip() == "Task complete.":
        return "done"
    return "status"


async def _broadcast(msg: str) -> None:
    """Send a message to all connected WebSocket clients (filtered for iOS)."""
    if not _should_send_to_ios(msg):
        return
    payload = json.dumps({
        "type": _infer_message_type(msg),
        "message": msg,
    })
    with clients_lock:
        dead = []
        for ws in clients:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            clients.discard(ws)


def _on_update(msg: str) -> None:
    """Callback from agent thread; schedule broadcast on main loop."""
    if event_loop and not event_loop.is_closed():
        asyncio.run_coroutine_threadsafe(_broadcast(msg), event_loop)


def _run_agent_loop() -> None:
    """Run the agent in a dedicated thread (Playwright requires same-thread)."""
    command_source = QueueCommandSource(command_queue, exit_sentinel=EXIT_SENTINEL)
    run_agent(command_source=command_source, on_update=_on_update)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    """WebSocket endpoint: receive commands, broadcast status updates."""
    await websocket.accept()
    with clients_lock:
        clients.add(websocket)

    try:
        while True:
            message = await websocket.receive()
            # Handle text or binary - iOS may send either depending on client impl
            if "text" in message:
                data = message["text"]
            elif "bytes" in message:
                data = message["bytes"].decode("utf-8", errors="replace")
            else:
                # Disconnect, ping/pong, etc - continue loop (disconnect will raise)
                continue
            try:
                obj = json.loads(data)
                command = obj.get("command", "").strip()
                if command:
                    command_queue.put(command)
                    preview = command[:50] + "..." if len(command) > 50 else command
                    await _broadcast(f"Command received: {preview}")
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": "Invalid JSON. Expected {\"command\": \"...\"}",
                }))
    except WebSocketDisconnect:
        pass
    finally:
        with clients_lock:
            clients.discard(websocket)


@app.get("/health")
async def health() -> dict:
    """Health check for monitoring."""
    return {"status": "ok", "clients": len(clients)}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8765,
        log_level="info",
    )
