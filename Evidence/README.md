# Evidence status

Captured from the real run across the four Macs, exported from the "Phase 1
Evidence" Figma page. Numbering follows the Final Demonstration Sequence
(doc Section 8), so file number roughly lines up with demo step number.
Status as of 2026-09-23:

| File | Status | What it shows |
|------|--------|----------------|
| `01-ping.png` | done | ping between all four Macs succeeding |
| `02-dns.png` | done | dig app.team1.test resolving to 10.7.20.225 |
| `03-backend-a-and-b.png` | done | both backends responding directly (combined, replaces separate 03/04 from the original template) |
| `04-https.png` | done | curl -v https://app.team1.test:8443/api/status, opened by domain name, matches demo step 4 |
| `05-load-balancing.png` | done | loop showing alternating X-Backend: A / B, matches demo step 5 |
| `06-dns-wireshark.png` | done | Wireshark, filter dns.qry.name=="app.team1.test", query and response, part of demo step 6 |
| `07-wireshark-tcp-tls-NOT-CAPTURED.png` | missing | TCP handshake and TLS handshake were never captured, the rest of demo step 6. Checked with tshark against the real pcap (~/Downloads/no_internet.pcapng): 0 of 115,838 packets match tcp.port==8443 or ip.addr==10.7.20.225. Best guess is that curl was run from the edge machine itself, so the connection to its own IP stayed on loopback and never crossed the interface Wireshark was watching. Topology is torn down now, so this can't be redone. Accepted as a known gap. |
| `08-http-cache.png` | done | curl -I showing the Cache-Control header, matches demo step 7 |
| `09-failure-tests/01-wrong-dns-server.png` | done | wrong DNS server, backend reachable but resolves wrong |
| `09-failure-tests/02-wrong-dns-record.png` | done | wrong DNS record, dig and curl showing the wrong IP and a refused connection |
| `09-failure-tests/03-one-backend-down.png` | done | Backend B (Mac D, Hemanth) was stopped, every request afterward came back X-Backend: A. Matches demo step 8, "fail one backend": the doc's demonstration step only says "fail one backend," the Mac 3 / Backend A example in its expected-observation column is illustrative, not a requirement to use that exact backend, so this counts |
| `09-failure-tests/04-both-backends-down.png` | done | TLS still works, but nginx returns 502 Bad Gateway |
| `09-failure-tests/05-wrong-destination-port.png` | done | bonus evidence, not in the original list. Host is pingable, wrong port gets refused |

Also exported: `../Architecture/topology-diagram.png` and `../Architecture/request-flow-diagram.png`.

## What's actually left

The TCP and TLS Wireshark captures are gone for good since the topology is torn down. Accepted, documented in `07-wireshark-tcp-tls-NOT-CAPTURED.png`, worth a one-line mention in the writeup as a known limitation. Everything else in this folder is captioned, numbered without gaps, and done.

Demo steps 1 to 3, 5 to 7, 9, and 10 from Section 8 still need to be re-run live once the topology is rebuilt, evidence existing doesn't replace the live demo requirement. Steps 4 and 8 already have matching evidence above. Step 11 (individual viva) has no file to prepare, it's answered live.
