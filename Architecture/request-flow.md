# Phase 1 Request Flow

Rendered version: [`request-flow-diagram.png`](request-flow-diagram.png).

## Sequence (what one `curl` does end-to-end)

```
Client (Mac C or D)                Mac A (DNS)        Mac B (nginx :8443)     Mac C/D (backend)
      │                                 │                     │                     │
      │  DNS query: app.team1.test     │                     │                     │
      │────────────UDP 53─────────────►│                     │                     │
      │◄────A record: 10.7.20.225──────│                     │                     │
      │                                 │                     │                     │
      │  TCP SYN ──────────────────────────────────────────► │                     │
      │  TCP SYN-ACK ◄───────────────────────────────────────│                     │
      │  TCP ACK ──────────────────────────────────────────► │                     │
      │                                 │                     │                     │
      │  TLS ClientHello ──────────────────────────────────► │                     │
      │  TLS ServerHello, Certificate ◄────────────────────── │                     │
      │  TLS Finished ─────────────────────────────────────► │                     │
      │                                 │                     │                     │
      │  GET /api/status (encrypted) ──────────────────────► │                     │
      │                                 │                     │  proxy_pass         │
      │                                 │                     │────────────────────►│
      │                                 │                     │◄──X-Backend: A/B────│
      │◄──HTTP/1.1 200 + X-Backend + Cache-Control────────────│                     │
```

## Layer summary

| Step | Protocol | Source → Destination        | Port         |
|------|----------|------------------------------|--------------|
| 1    | DNS      | Client → Mac A                | UDP 53       |
| 2    | TCP      | Client → Mac B                | TCP 8443     |
| 3    | TLS      | Client ↔ Mac B                | TCP 8443     |
| 4    | HTTP(S)  | Client ↔ Mac B (encrypted)    | TCP 8443     |
| 5    | HTTP     | Mac B → Mac C or Mac D        | TCP 3001/3002|
