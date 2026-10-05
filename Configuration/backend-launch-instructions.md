# Backend Launch Instructions

Both backends are plain Python, no dependencies beyond the standard library. Python 3 is all you need.

## Backend A, on Mac C (Arina)

```bash
cd Backends/backend-a
python3 server.py
```

Starts on `0.0.0.0:3001`, reachable from the LAN, not just localhost. You should see:

```
Backend A running on port 3001
```

## Backend B, on Mac D (Hemanth)

```bash
cd Backends/backend-b
python3 server.py
```

Starts on `0.0.0.0:3002`. You should see:

```
Backend B running on port 3002
```

## Quick local check, before nginx is even in the picture

From the same machine the backend is running on:

```bash
curl -i http://localhost:3001/api/status
# {"backend": "A", "status": "ok"}, with X-Backend: A and Cache-Control: max-age=60 in the headers
```

From another Mac on the LAN, confirm it is reachable over the network too:

```bash
curl -i http://10.7.13.142:3001/api/status   # Backend A
curl -i http://10.7.20.219:3002/api/status   # Backend B
```

If either of those LAN checks fails while the localhost check works, the backend is bound to `127.0.0.1` instead of `0.0.0.0`. Both `server.py` files already bind to `0.0.0.0`, so this should not come up unless something else changed.

## Stopping a backend, for the failure demos

`Ctrl+C` in the terminal it is running in. No PID lookup needed since it runs in the foreground.
