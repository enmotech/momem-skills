#!/usr/bin/env python3
"""Render :name SQL placeholders from SQL_PARAM_name environment variables."""

import os
import re
import sys
from pathlib import Path


RAW_NUMBER_PARAMS = {
    "memory_count",
    "similarity_threshold",
    "top_k",
}


def sql_literal(name: str) -> str:
    """Return a SQL literal for a named parameter."""
    value = os.environ.get(f"SQL_PARAM_{name}", "")
    if value == "":
        return "NULL"
    if name in RAW_NUMBER_PARAMS:
        return value
    return "'" + value.replace("'", "''") + "'"


def render(sql: str) -> str:
    """Replace :name placeholders while preserving PostgreSQL :: casts."""
    return re.sub(
        r"(?<!:):([A-Za-z_][A-Za-z0-9_]*)",
        lambda match: sql_literal(match.group(1)),
        sql,
    )


def main() -> int:
    """Render the SQL file passed as the only argument to stdout."""
    if len(sys.argv) != 2:
        print("usage: render_sql.py <sql-file>", file=sys.stderr)
        return 2

    sql_path = Path(sys.argv[1])
    print(render(sql_path.read_text()), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
