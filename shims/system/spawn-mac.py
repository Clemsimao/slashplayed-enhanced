#!/usr/bin/env python3
"""Mac stand-in for `devicectl process launch --start-stopped` + lldb attach, keeping the exit status.

Usage: spawn-mac.py <jit.py mode> <stdout> <stderr> <program> [args...]

Spawns the program suspended (POSIX_SPAWN_START_SUSPENDED), attaches lldb with research/jittest/jit.py
to service brk #0xf00d, then waits for the program and exits with its status (128 + n for signal n).
"""
import ctypes
import os
import subprocess
import sys

POSIX_SPAWN_START_SUSPENDED = 0x0080

mode, out, err, prog = sys.argv[1:5]
argv = sys.argv[4:]
libc = ctypes.CDLL(None, use_errno=True)
attr = ctypes.c_void_p()
acts = ctypes.c_void_p()
libc.posix_spawnattr_init(ctypes.byref(attr))
libc.posix_spawnattr_setflags(ctypes.byref(attr), ctypes.c_short(POSIX_SPAWN_START_SUSPENDED))
libc.posix_spawn_file_actions_init(ctypes.byref(acts))
for fd, path in ((1, out), (2, err)):
    libc.posix_spawn_file_actions_addopen(ctypes.byref(acts), fd, path.encode(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                                          0o644)
c_argv = (ctypes.c_char_p * (len(argv) + 1))(*[a.encode() for a in argv], None)
c_env = (ctypes.c_char_p * (len(os.environ) + 1))(*[f"{k}={v}".encode() for k, v in os.environ.items()], None)
pid = ctypes.c_int()
rc = libc.posix_spawn(ctypes.byref(pid), prog.encode(), ctypes.byref(acts), ctypes.byref(attr), c_argv, c_env)
if rc:
    sys.exit(f"posix_spawn: {os.strerror(rc)}")
print(f"spawned pid {pid.value}", flush=True)

jit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../research/jittest/jit.py")
lldb = subprocess.run(["xcrun", "lldb", "-b", prog, "-o", f"command script import {jit}",
                       "-o", f"process attach -p {pid.value}", "-o", f"spjit {mode}"],
                      stdin=subprocess.DEVNULL, capture_output=True, text=True)
for line in lldb.stdout.splitlines():
    if line.startswith("[spjit]") or "error" in line:
        print(line)

_, status = os.waitpid(pid.value, 0)
if os.WIFSIGNALED(status):
    print(f"exited on signal {os.WTERMSIG(status)}")
    sys.exit(128 + os.WTERMSIG(status))
print(f"exit status {os.WEXITSTATUS(status)}")
sys.exit(os.WEXITSTATUS(status))
