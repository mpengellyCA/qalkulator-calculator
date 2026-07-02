# QalKulator as an MCP server

QalKulator can expose the [libqalculate](https://qalculate.github.io/) engine to an
AI agent over the [Model Context Protocol](https://modelcontextprotocol.io). The
design goal is **visibility**: when an agent does maths through QalKulator, it does
it in front of you.

- Each agent session opens its **own window** bound to a dedicated calculator
  instance (its own engine + result tape, its own accent colour).
- That window is **read-only** to you — there is no input field or keypad, just a
  live tape. The agent drives it entirely over MCP; you watch every expression and
  result appear.
- Close the window to end the session; end the session and the window closes.

The feature is **off by default** and only ever listens on the loopback interface,
guarded by a shared token.

## Enabling it

Settings (`Ctrl+,`) → **AI agents (MCP)** → tick *Let AI agents use the engine*.

QalKulator then shows everything an MCP client needs:

- **Server URL** — `http://127.0.0.1:<port>/mcp` (HTTP transport).
- **Token** — the shared secret the client must present (copy, or regenerate).
- **stdio command** — the path to `qalkulator-mcp` for clients that only speak stdio.

The server must be running (QalKulator open with MCP enabled) for an agent to
connect.

## Two transports

QalKulator serves MCP over **Streamable HTTP**, and ships a small **stdio bridge**
for clients that only support stdio. Both reach the same server and open the same
kind of read-only window.

### HTTP (Streamable HTTP)

Point an HTTP-capable MCP client at the URL and send the token as a bearer header.
Example client configuration:

```json
{
  "mcpServers": {
    "qalkulator": {
      "url": "http://127.0.0.1:47600/mcp",
      "headers": { "Authorization": "Bearer <token-from-settings>" }
    }
  }
}
```

### stdio (`qalkulator-mcp`)

For clients that launch a command and talk over stdin/stdout:

```json
{
  "mcpServers": {
    "qalkulator": {
      "command": "qalkulator-mcp"
    }
  }
}
```

The bridge reads the port and token from QalKulator's own config
(`qalkulatorrc`), so no arguments are needed. You can override them with the
`QALKULATOR_MCP_PORT` and `QALKULATOR_MCP_TOKEN` environment variables.

## Tools

| Tool | Arguments | Result |
| --- | --- | --- |
| `calculate` | `expression` | Evaluates an expression (units, constants, functions, percentages). Use the `to`/`->` operator for conversions, e.g. `5 km to miles`. |
| `convert` | `value`, `from`, `to` | Converts a quantity between units or currencies, e.g. `100` `USD` → `EUR`. |
| `get_history` | — | Returns every calculation performed in this session (expression + result). |
| `clear` | — | Clears the tape shown in the window. |

Every `calculate`/`convert` result is appended to the agent's window as it happens.

## Notes & limits

- **Loopback only.** The server binds `127.0.0.1`; the token stops other local
  processes from driving it. Treat the token like a password.
- **Conversions:** prefer the `to`/`->` operator (or the `convert` tool). The bare
  word `in` is the *inch* unit to libqalculate, so `5 km in miles` is a
  multiplication, not a conversion — write `5 km to miles`.
- **Port fallback.** If the configured port (default `47600`) is taken, the server
  tries the next few; the stdio bridge probes the same small range.
- **Session lifecycle.** A session lasts until the agent sends an MCP `DELETE`, or
  you close its window. There is no fixed cap on concurrent sessions — each is a
  window you can see and close.
