"""lldb side of the brk #0xf00d JIT protocol (see main.c). Load with `command script import jit.py`,
then run `spjit [mode]` once attached to a stopped process.

Prepare writes each 16 KB page's own bytes back, so it marks pages for the debugger without
changing their contents (StikDebug's universal.js writes 0x69 instead). `spjit <mode>` picks how:
  page  (default) read and write the first byte of each page: two round trips per page
  pagew write one byte per page, taking the bytes from the app's x2 buffer (one read) if given,
        else reading the region in bulk: one round trip per page
  bulk  read the region in bulk and write all of it back in large chunks
  bulkz write zeros over the whole region in large chunks, without reading. Destroys the contents;
        only valid when the caller overwrites every byte next (the client's startup code rewrite does)
  bulkx as bulkz, but writes 'A's with raw binary X packets (half the round trips of lldb's hex M)
"""
import os
import time

import lldb

BRK_F00D = 0xD43E01A0
PAGE = 0x4000


def _reg(frame, name):
    return frame.FindRegister(name).GetValueAsUnsigned()


def _set_reg(frame, name, value):
    err = lldb.SBError()
    frame.FindRegister(name).SetValueFromCString(hex(value), err)
    if err.Fail():
        raise RuntimeError(f"set {name}: {err}")


CHUNK = 1 << 20
XCHUNK = 0x1fc00  # X packet payload; debugserver's PacketSize is 0x20000


def _log(msg):
    # With SP_JIT_T0 (clienttest/run.sh), prefix seconds since then; else wall-clock time.
    t0 = os.environ.get("SP_JIT_T0")
    stamp = f"{time.time() - float(t0):.2f}" if t0 else time.strftime("%H:%M:%S")
    print(f"[spjit] {stamp} {msg}", flush=True)


def _read_bulk(process, addr, length):
    err = lldb.SBError()
    parts = []
    for off in range(0, length, CHUNK):
        b = process.ReadMemory(addr + off, min(CHUNK, length - off), err)
        if err.Fail():
            raise RuntimeError(f"read 0x{addr + off:x}: {err}")
        parts.append(b)
    return b"".join(parts)


def _prepare_fast(process, addr, length, mode, firsts):
    err = lldb.SBError()
    start = time.time()
    if mode == "pagew" and firsts:
        data = process.ReadMemory(firsts, length // PAGE, err)
        if err.Fail():
            raise RuntimeError(f"read firsts 0x{firsts:x}: {err}")
        first = lambda off: data[off // PAGE:off // PAGE + 1]
    elif mode == "bulkz":
        data = bytes(length)
    elif mode == "bulkx":
        data = None
    else:
        data = _read_bulk(process, addr, length)
        first = lambda off: data[off:off + 1]
    t_read = time.time() - start
    failures = 0
    if mode == "bulkx":
        # Binary X packets: lldb's own writes use hex M packets, half the payload per round trip. 'A'
        # needs no escaping and no NUL in the command string. The headset writes the ",len:" header
        # too, as data, so each chunk's payload is cut by the header's length: then a chunk writes at
        # most n bytes whether or not the header is written (if not, its last few bytes go unwritten,
        # inside a page the next chunk touches). Checked below: the bytes just past the region must
        # not change.
        interp = process.GetTarget().GetDebugger().GetCommandInterpreter()

        def packet(p):
            res = lldb.SBCommandReturnObject()
            interp.HandleCommand(f'process plugin packet send "{p}"', res)
            out = res.GetOutput()
            return out[out.rfind("response: ") + 10:].strip() if "response: " in out else res.GetError()

        after = packet(f"m{addr + length:x},10")
        for off in range(0, length, XCHUNK):
            n = min(XCHUNK, length - off)
            m = n - len(f",{n:x}:")  # header of m is no longer than that of n: never more than n
            r = packet(f"X{addr + off:x},{m:x}:{'A' * m}")
            if r != "OK":
                failures += 1
                if failures <= 3:
                    _log(f"X 0x{addr + off:x} failed: {r}")
        if packet(f"m{addr + length:x},10") != after:
            raise RuntimeError(f"bulkx wrote past 0x{addr + length:x}")
    elif mode == "pagew":
        for off in range(0, length, PAGE):
            process.WriteMemory(addr + off, first(off), err)
            if err.Fail():
                failures += 1
                if failures <= 3:
                    _log(f"write 0x{addr + off:x} failed: {err}")
    else:
        for off in range(0, length, CHUNK):
            n = min(CHUNK, length - off)
            if process.WriteMemory(addr + off, data[off:off + n], err) != n or err.Fail():
                failures += 1
                if failures <= 3:
                    _log(f"write 0x{addr + off:x} failed: {err}")
    total = time.time() - start
    _log(f"prepared ({mode}) 0x{addr:x}+0x{length:x}: {length // PAGE} pages, {failures} failures, "
         f"read {t_read:.2f}s, total {total:.2f}s ({total * 1000 / (length // PAGE):.2f} ms/page)")
    return addr


def _prepare(process, addr, length, mode="page", firsts=0):
    if addr and mode != "page":
        return _prepare_fast(process, addr, length, mode, firsts)
    err = lldb.SBError()
    if addr == 0:
        addr = process.AllocateMemory(length, lldb.ePermissionsReadable | lldb.ePermissionsExecutable, err)
        if err.Fail():
            _log(f"AllocateMemory failed: {err}")
            return 0
        _log(f"allocated 0x{addr:x}")
    start = time.time()
    failures = 0
    for page in range(addr, addr + length, PAGE):
        b = process.ReadMemory(page, 1, err)
        if err.Fail():
            failures += 1
            if failures <= 3:
                _log(f"read 0x{page:x} failed: {err}")
            continue
        process.WriteMemory(page, b, err)
        if err.Fail():
            failures += 1
            if failures <= 3:
                _log(f"write 0x{page:x} failed: {err}")
    pages = length // PAGE
    total = time.time() - start
    _log(f"prepared 0x{addr:x}+0x{length:x}: {pages} pages, {failures} failures, "
         f"{total:.2f}s ({total * 1000 / pages:.2f} ms/page)")
    return addr


def _stopped_thread(process):
    return next((t for t in process if t.GetStopReason() not in
                 (lldb.eStopReasonNone, lldb.eStopReasonInvalid)), None)


def serve(process, mode):
    """Runs the brk #0xf00d protocol until the app detaches, exits or stops unexpectedly."""
    # `device process attach` can return before lldb has the thread list. Continuing then is a no-op
    # that leaves lldb refusing register writes at the next stop, so wait for the attach to finish.
    for _ in range(150):
        if process.GetNumThreads() > 0:
            break
        time.sleep(0.2)
    _log(f"attached: {process.GetNumThreads()} threads, stop id {process.GetStopID()}")
    spurious = 0
    foreign_breaks = 0
    resume = True
    while True:
        if resume:
            process.Continue()
        resume = True
        state = process.GetState()
        if state == lldb.eStateExited:
            _log(f"exited: status={process.GetExitStatus()} {process.GetExitDescription() or ''}")
            return
        if state != lldb.eStateStopped:
            _log(f"state {lldb.SBDebugger.StateAsCString(state)}")
            return
        thread = _stopped_thread(process)
        if thread is None:
            # Continue() can return "stopped" before the real stop, with no stop reason. Wait for the
            # real stop rather than calling it again.
            for _ in range(50):
                time.sleep(0.2)
                thread = _stopped_thread(process)
                if thread is not None or process.GetState() != lldb.eStateStopped:
                    break
            spurious += 1
            if thread is not None or process.GetState() != lldb.eStateStopped:
                resume = False
            continue
        if spurious:
            _log(f"{spurious} early returns with no stop reason")
            spurious = 0
        frame = thread.GetFrameAtIndex(0)
        pc = frame.GetPC()
        err = lldb.SBError()
        insn = process.ReadUnsignedFromMemory(pc, 4, err)
        if err.Success() and insn == BRK_F00D:
            cmd = _reg(frame, "x16")
            if cmd == 1:
                _log("prepare request")
                try:
                    addr = _prepare(process, _reg(frame, "x0"), _reg(frame, "x1"), mode, _reg(frame, "x2"))
                except RuntimeError as e:
                    _log(f"prepare failed: {e}; killing the process")
                    process.Kill()
                    return
                _set_reg(frame, "x0", addr)
                _set_reg(frame, "pc", pc + 4)
                continue
            if cmd == 0:
                _set_reg(frame, "pc", pc + 4)
                _log("detaching")
                process.Detach()
                return
            _log(f"unknown command {cmd}")
        elif foreign_breaks < 5 and thread.GetStopReason() in (lldb.eStopReasonBreakpoint, lldb.eStopReasonException):
            # Sometimes (often the first launch after an install) lldb reports "error reading data from
            # section __text" and then stops in dyld on a breakpoint that isn't ours, most likely its own
            # image-notifier breakpoint that it no longer recognizes. Continue past it.
            foreign_breaks += 1
            word = f"0x{insn:08x}" if err.Success() else f"unreadable ({err})"
            _log(f"continuing past a stop that isn't ours: {thread.GetStopDescription(256)} "
                 f"at pc=0x{pc:x}, instruction {word}")
            continue
        _log(f"stopped: {thread.GetStopDescription(256)} at pc=0x{pc:x}")
        for f in thread.frames[:6]:
            _log(f"  {f}")
        process.Kill()
        return


def spjit(debugger, command, result, internal_dict):
    debugger.SetAsync(False)
    serve(debugger.GetSelectedTarget().GetProcess(), command.strip() or "page")


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(f"command script add -f {__name__}.spjit spjit")


