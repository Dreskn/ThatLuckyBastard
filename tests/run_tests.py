"""Loads the addon into a real Lua 5.1 engine with stand-ins for the game
(harness.lua), then runs the Lua test script given as second argument.

    python run_tests.py <addon dir> <test.lua> [saved variables file]
"""
import io
import os
import re
import sys

from lupa import lua51

here = os.path.dirname(os.path.abspath(__file__))
addon_dir, test_file = sys.argv[1], sys.argv[2]
saved = sys.argv[3] if len(sys.argv) > 3 else None

lua = lua51.LuaRuntime(unpack_returned_tuples=True)


def run(path, name=None):
    src = io.open(path, encoding='utf-8').read()
    lua.globals().__src = src
    lua.execute('local f, err = loadstring(__src, "@%s"); if not f then error(err, 0) end; f()' % (name or os.path.basename(path)))


run(os.path.join(here, 'harness.lua'))
if saved:
    run(saved, 'SavedVariables')

# Files in the order the .toc lists them.
toc = io.open(os.path.join(addon_dir, 'ThatLuckyBastard.toc'), encoding='utf-8').read()
files = [line.strip() for line in toc.splitlines() if re.match(r'^[\w./\\-]+\.lua$', line.strip())]
load = lua.globals().LoadAddonFile
for f in files:
    load(f, io.open(os.path.join(addon_dir, f), encoding='utf-8').read())
print('loaded: ' + ', '.join(files))

lua.globals().TEST_DIR = here.replace(os.sep, '/')
lua.execute('function Include(name) local f = assert(loadfile(TEST_DIR .. "/" .. name)); return f() end')
run(test_file)
sys.exit(1 if lua.globals().FAILED else 0)
