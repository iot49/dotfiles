"""Read and write implement-loop's run state.

Kept beside the script rather than inline, because the shell heredoc that
would hold it sits inside a function that is itself quoted in places.

  read  <file>                                  -> ST_* shell assignments
  write <file> <ts> <branch> <start> <order> <landed> <preskip> <pr> <phase>
"""

import json
import os
import sys

FIELDS = ("ts", "branch", "start_sha", "order", "landed", "preskip", "pr_url", "phase")


def quote(v):
    return "'" + str(v).replace("'", "'\\''") + "'"


def main(argv):
    if argv[1] == "read":
        try:
            d = json.load(open(argv[2]))
        except Exception:
            d = {}
        for k in FIELDS:
            print("ST_%s=%s" % (k.upper(), quote(d.get(k, ""))))
        return 0

    if argv[1] == "write":
        path = argv[2]
        d = dict(zip(FIELDS, argv[3:11]))
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(d, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)
        return 0

    sys.stderr.write("usage: il-state.py read|write ...\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
