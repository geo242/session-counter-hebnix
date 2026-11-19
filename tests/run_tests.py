"""Run the Session Counter plugin against a mocked Hebnix host in Lua 5.4.

Hebnix embeds Lua 5.4 (mlua), and lupa ships the same version, so no system Lua is needed.

    python -m pip install lupa
    python tests/run_tests.py
"""

import json
import sys
from pathlib import Path

from lupa import lua54

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    lua = lua54.LuaRuntime()

    def to_py(value):
        if lua54.lua_type(value) != "table":
            return value
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(value[k]) for k in sorted(keys)]
        return {str(k): to_py(value[k]) for k in keys}

    def to_lua(value):
        if isinstance(value, (dict, list)):
            return lua.table_from(value, recursive=True)
        return value

    g = lua.globals()
    def encode(value):
        try:
            return json.dumps(to_py(value))
        except Exception as error:
            print(f"json_encode failed: {error!r}")
            raise

    g.py_json_encode = encode
    g.py_json_decode = lambda text: to_lua(json.loads(text))
    g.arg_path = str(ROOT / "session_counter" / "main.lua")
    harness = (ROOT / "tests" / "harness.lua").read_text(encoding="utf-8")
    try:
        lua.execute(harness)
    except Exception as error:  # Lua errors surface as LuaError
        print(f"FAILED: {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
