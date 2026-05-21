import argparse
import sys
import time

import requests


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True, help="Gateway health URL to poll")
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--interval-seconds", type=float, default=2.0)
    args = parser.parse_args()

    deadline = time.time() + args.timeout_seconds
    last_error = "no attempts made"

    while time.time() < deadline:
        try:
            resp = requests.get(args.url, timeout=10)
            if resp.status_code == 200:
                print(f"Gateway is ready: {args.url}")
                return 0
            last_error = f"status={resp.status_code}, body={resp.text[:300]}"
        except Exception as exc:
            last_error = str(exc)
        time.sleep(args.interval_seconds)

    print(f"Gateway readiness timeout. Last error: {last_error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
