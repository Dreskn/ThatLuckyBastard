"""Compiles each Lua file given on the command line with a real Lua engine
(Lua 5.1 when lupa ships it, which is what the game runs). Nothing is
executed. With Lua 5.1 it also reads each file's bytecode for two more
checks, which cover every line whether a test runs it or not:

- Limits: Lua refuses to load a file with more than 200 local variables
  alive at once in its main chunk, or a function using more than 60
  variables from outside it (upvalues). A file fails here well before
  that, at MAX_LOCALS and MAX_UPVALUES.
- Globals: every global name a file reads or writes must be listed in
  tests/globals.txt. A name missing there is a typo, or a local that a
  file uses without having it (say, after code moved to another file).
  A new game function the addon starts using is added to the list.

    python luacheck.py <file.lua> ...
"""
import io
import os
import sys

try:
    from lupa import lua51 as engine
    which = 'Lua 5.1'
except ImportError:
    import lupa as engine
    which = 'Lua %s.%s' % engine.LUA_VERSION

MAX_LOCALS = 180
MAX_UPVALUES = 50

lua = engine.LuaRuntime(unpack_returned_tuples=True, encoding=None)
load = lua.eval(b'function(src, name) local f, err = (loadstring or load)(src, name); return f ~= nil, err end')
dump = lua.eval(b'function(src, name) return string.dump(assert((loadstring or load)(src, name))) end')


class Bytecode:
    """Reads a Lua 5.1 string.dump: per function, its most locals alive at
    once, its upvalue count, and the global names it reads and writes."""

    def __init__(self, data):
        self.d = data
        self.int_size, self.size_t, self.instr_size, self.num_size = data[7], data[8], data[9], data[10]
        self.p = 12
        self.functions, self.reads, self.writes = [], set(), set()
        self.function()

    def byte(self):
        self.p += 1
        return self.d[self.p - 1]

    def int(self, size=None):
        size = size or self.int_size
        self.p += size
        return int.from_bytes(self.d[self.p - size:self.p], 'little')

    def string(self):
        n = self.int(self.size_t)
        self.p += n
        return self.d[self.p - n:self.p - 1].decode('utf-8', 'replace') if n else ''

    def function(self):
        self.string()
        line, last = self.int(), self.int()
        upvalues = self.byte()
        self.p += 3
        code = [self.int(self.instr_size) for _ in range(self.int())]
        constants = []
        for _ in range(self.int()):
            kind = self.byte()
            if kind == 1:
                self.p += 1
            elif kind == 3:
                self.p += self.num_size
            constants.append(self.string() if kind == 4 else None)
        for ins in code:
            op, bx = ins & 0x3F, ins >> 14
            if op == 5:    # GETGLOBAL
                self.reads.add(constants[bx])
            elif op == 7:  # SETGLOBAL
                self.writes.add(constants[bx])
        info = {'line': line, 'upvalues': upvalues}
        self.functions.append(info)
        for _ in range(self.int()):
            self.function()
        lines = self.int()  # line info, not needed
        self.p += lines * self.int_size
        events = []
        for _ in range(self.int()):
            self.string()
            events += [(self.int(), 1), (self.int(), -1)]
        alive = most = 0
        for _, step in sorted(events):
            alive += step
            most = max(most, alive)
        info['locals'] = most
        for _ in range(self.int()):
            self.string()


allowed = set()
listed = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'globals.txt')
for line in io.open(listed, encoding='utf-8'):
    line = line.split('#')[0].strip()
    if line:
        allowed.update(line.split())

bad = 0
for path in sys.argv[1:]:
    src = io.open(path, encoding='utf-8').read().encode('utf-8')
    ok, err = load(src, b'@' + path.encode())
    if not ok:
        bad += 1
        print('%-32s %s' % (path, err.decode() if isinstance(err, bytes) else err))
        continue
    if which != 'Lua 5.1':
        print('%-32s ok' % path)
        continue
    code = Bytecode(dump(src, b'@' + path.encode()))
    main = code.functions[0]
    worst = max(code.functions[1:], key=lambda f: f['upvalues'], default={'upvalues': 0, 'line': 0})
    problems = []
    if main['locals'] > MAX_LOCALS:
        problems.append('%d top-level locals, over %d' % (main['locals'], MAX_LOCALS))
    for f in code.functions[1:]:
        if f['upvalues'] > MAX_UPVALUES:
            problems.append('function at line %d uses %d upvalues, over %d' % (f['line'], f['upvalues'], MAX_UPVALUES))
    unknown = sorted((code.reads | code.writes) - allowed)
    if unknown:
        problems.append('globals not in tests/globals.txt: ' + ' '.join(unknown))
    bad += 1 if problems else 0
    print('%-32s %s  locals %3d/200  upvalues %2d/60 (line %d)' % (
        path, 'ok  ' if not problems else 'FAIL', main['locals'], worst['upvalues'], worst['line']))
    for problem in problems:
        print('    ' + problem)
print(which, '-', 'all files pass' if not bad else '%d file(s) failing' % bad)
sys.exit(1 if bad else 0)
