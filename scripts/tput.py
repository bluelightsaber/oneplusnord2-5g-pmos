#!/usr/bin/env python3
"""Tiny one-shot TCP throughput endpoint (no iperf3 on the host).
   tput.py sink HOST PORT   -> accept one connection, read until EOF, print MB and Mbit/s
   tput.py source HOST PORT SECONDS -> accept one connection, send zeros for SECONDS, print rate"""
import socket, sys, time
mode, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((host, port)); s.listen(1)
s.settimeout(120); c, a = s.accept(); t0 = time.time(); n = 0
if mode == 'sink':
    while True:
        b = c.recv(1 << 16)
        if not b: break
        n += len(b)
else:
    buf = bytes(1 << 16); dur = float(sys.argv[4])
    while time.time() - t0 < dur:
        n += c.send(buf)
    c.close()
dt = time.time() - t0
print(f"{mode}: {n/1e6:.1f} MB in {dt:.1f} s = {n*8/dt/1e6:.1f} Mbit/s")
