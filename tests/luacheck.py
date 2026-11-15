"""Compiles each Lua file given on the command line with a real Lua engine
(Lua 5.1 when lupa ships it, which is what the game runs). Compiling only:
nothing is executed, so this catches syntax errors, not runtime ones."""
import io
import sys

try:
    from lupa import lua51 as engine
    which = 'Lua 5.1'
except ImportError:
    import lupa as engine
    which = 'Lua %s.%s' % engine.LUA_VERSION

lua = engine.LuaRuntime(unpack_returned_tuples=True)
load = lua.eval('function(src, name) local f, err = (loadstring or load)(src, name); return f ~= nil, err end')

bad = 0
for path in sys.argv[1:]:
    src = io.open(path, encoding='utf-8').read()
    ok, err = load(src, '@' + path)
    if not ok:
        bad += 1
    print('%-28s %s' % (path, 'ok' if ok else err))
print(which, '-', 'all files compile' if not bad else '%d file(s) with errors' % bad)
sys.exit(1 if bad else 0)
