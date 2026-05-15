#!/usr/bin/env python3
"""
Unified Load Testing Script for KEDA Autoscaling Validation.
Replaces previous random_transfers.py and seed_users.py.

Usage:
  python load_test.py --scenario auth --users 50 --rps 20 --duration 60 --base-url http://banking.local

Scenarios:
- auth: Rapidly calls /api/auth/health (no auth).
- account: Rapidly calls /api/account/balance.
- transfer: Rapidly calls /api/transfer/transfer between random users.
- all: Spawns load across all endpoints.

User data is cached in users.csv (phone, password, session, balance, account_number).
If sessions are invalid, the script logs in with phone/password to refresh them.
"""

import argparse
import asyncio
import csv
import random
import string
import sys
import time
from pathlib import Path

try:
    import requests
    import aiohttp
except ImportError:
    print("Please install requirements: pip install -r requirements.txt")
    sys.exit(1)


def random_phone(index: int) -> str:
    n = 10000000 + (index % 90000000)
    return f"09{n:08d}"


def random_string(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=length))


USERS_CSV = Path(__file__).with_name("users.csv")
CSV_FIELDS = ["phone", "password", "session",
              "balance", "account_number", "username"]


def _safe_int(value: str | None) -> int | None:
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def read_users_csv(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        users = []
        for row in reader:
            if not row:
                continue
            users.append(
                {
                    "phone": (row.get("phone") or "").strip(),
                    "password": (row.get("password") or "").strip(),
                    "session": (row.get("session") or "").strip(),
                    "balance": _safe_int((row.get("balance") or "").strip()),
                    "account_number": (row.get("account_number") or "").strip(),
                    "username": (row.get("username") or "").strip(),
                }
            )
        return [u for u in users if u["phone"] and u["password"]]


def write_users_csv(path: Path, users: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for u in users:
            writer.writerow(
                {
                    "phone": u.get("phone", ""),
                    "password": u.get("password", ""),
                    "session": u.get("session", ""),
                    "balance": "" if u.get("balance") is None else str(u.get("balance")),
                    "account_number": u.get("account_number", ""),
                    "username": u.get("username", ""),
                }
            )


def validate_session(session: requests.Session, base_url: str, token: str) -> int | None:
    if not token:
        return None
    try:
        r = session.get(
            f"{base_url}/api/account/balance",
            headers={"x-session": token},
            timeout=5,
        )
        if r.status_code == 200:
            return r.json().get("balance")
    except Exception:
        return None
    return None


def login_user(session: requests.Session, base_url: str, phone: str, password: str) -> dict | None:
    payload = {"phone": phone, "password": password}
    try:
        r = session.post(f"{base_url}/api/auth/login", json=payload, timeout=5)
        if r.status_code == 200:
            data = r.json()
            return {
                "session": data.get("session"),
                "balance": data.get("balance"),
                "account_number": data.get("account_number"),
                "username": data.get("username"),
            }
    except Exception:
        return None
    return None


def register_user(session: requests.Session, base_url: str, phone: str, username: str, password: str) -> dict | None:
    payload = {"phone": phone, "username": username, "password": password}
    try:
        r = session.post(f"{base_url}/api/auth/register",
                         json=payload, timeout=5)
        if r.status_code == 200:
            return r.json()
    except Exception:
        return None
    return None


def refresh_user(session: requests.Session, base_url: str, user: dict) -> dict | None:
    balance = validate_session(session, base_url, user.get("session", ""))
    if balance is not None:
        user["balance"] = balance
        if user.get("account_number"):
            return user
        login = login_user(session, base_url, user["phone"], user["password"])
        if login and login.get("session"):
            user["session"] = login.get("session")
            user["balance"] = login.get("balance")
            user["account_number"] = login.get(
                "account_number") or user.get("account_number")
            user["username"] = login.get("username") or user.get("username")
            return user
        return user

    login = login_user(session, base_url, user["phone"], user["password"])
    if login and login.get("session"):
        user["session"] = login.get("session")
        user["balance"] = login.get("balance")
        user["account_number"] = login.get(
            "account_number") or user.get("account_number")
        user["username"] = login.get("username") or user.get("username")
        return user
    return None


def setup_users(base_url: str, num_users: int, csv_path: Path = USERS_CSV):
    """Registers/logs in users, validates sessions, and caches them to CSV."""
    base_url = base_url.rstrip("/")
    existing = read_users_csv(csv_path)
    users = []
    min_required = max(num_users, 2)

    print(f"[*] Setting up {min_required} users for load testing...")

    with requests.Session() as session:
        for u in existing:
            updated = refresh_user(session, base_url, u)
            if updated:
                users.append(updated)

        attempts = 0
        while len(users) < min_required and attempts < min_required * 5:
            attempts += 1
            phone = random_phone(random.randint(1, 999999) + attempts)
            username = f"user_{random_string()}"
            password = "Password123!"

            reg = register_user(session, base_url, phone, username, password)
            login = login_user(session, base_url, phone, password)
            if login and login.get("session"):
                users.append(
                    {
                        "phone": phone,
                        "password": password,
                        "session": login.get("session"),
                        "balance": login.get("balance"),
                        "account_number": login.get("account_number") or (reg or {}).get("account_number"),
                        "username": login.get("username") or username,
                    }
                )

            if len(users) % 10 == 0 and len(users) > 0:
                print(f"    ... {len(users)}/{min_required} ready.")

    write_users_csv(csv_path, users)
    print(f"[+] Ready users: {len(users)} (saved to {csv_path.name}).")
    return users


async def worker(worker_id: int, base_url: str, users: list, scenario: str, end_time: float, rps_per_worker: int):
    """Async worker hitting APIs to generate load."""
    sleep_time = 1.0 / rps_per_worker if rps_per_worker > 0 else 0

    async with aiohttp.ClientSession() as session:
        success, failed = 0, 0
        while time.time() < end_time:
            user = random.choice(users)
            x_session = user.get("session")
            if not x_session:
                failed += 1
                await asyncio.sleep(sleep_time)
                continue

            current_scenario = scenario
            if scenario == "all":
                current_scenario = random.choice(
                    ["auth", "account", "transfer"])

            try:
                start_req = time.time()
                if current_scenario == "auth":
                    # Auth service has no /me route, hitting health instead just for RPS load on auth service.
                    # If you want true business logic load, login again.
                    async with session.get(f"{base_url}/api/auth/health") as r:
                        await r.text()
                        if r.status == 200:
                            success += 1
                        else:
                            failed += 1

                elif current_scenario == "account":
                    async with session.get(f"{base_url}/api/account/balance", headers={"x-session": x_session}) as r:
                        await r.text()
                        if r.status == 200:
                            success += 1
                        else:
                            failed += 1

                elif current_scenario == "transfer":
                    if len(users) < 2:
                        failed += 1
                        await asyncio.sleep(sleep_time)
                        continue
                    sender_account = user.get("account_number")
                    target = random.choice(users)
                    while target is user or (
                        sender_account and target.get(
                            "account_number") == sender_account
                    ):
                        target = random.choice(users)
                    target_account = target.get("account_number")
                    if not target_account:
                        failed += 1
                        await asyncio.sleep(sleep_time)
                        continue
                    payload = {
                        "to_account_number": target_account,
                        "amount": 1,
                    }
                    async with session.post(f"{base_url}/api/transfer/transfer", headers={"x-session": x_session}, json=payload) as r:
                        await r.text()
                        if r.status == 200:
                            success += 1
                        else:
                            failed += 1

                elapsed = time.time() - start_req
                await asyncio.sleep(max(0, sleep_time - elapsed))

            except Exception:
                failed += 1
                await asyncio.sleep(sleep_time)

    return success, failed


async def run_load_test(base_url: str, users: list, scenario: str, duration: int, rps: int, workers: int):
    print(
        f"[*] Starting load test: Scenario='{scenario}', Duration={duration}s, Target RPS={rps}")
    end_time = time.time() + duration
    rps_per_worker = rps / workers

    tasks = []
    for i in range(workers):
        tasks.append(worker(i, base_url, users,
                     scenario, end_time, rps_per_worker))

    results = await asyncio.gather(*tasks)

    total_success = sum(r[0] for r in results)
    total_failed = sum(r[1] for r in results)
    print(f"[+] Load test complete.")
    print(f"    Total Successful Requests: {total_success}")
    print(f"    Total Failed Requests:     {total_failed}")
    print(
        f"    Actual RPS:                {(total_success + total_failed) / duration:.2f}")


def main():
    parser = argparse.ArgumentParser(
        description="Unified Load Test for Banking Services")
    parser.add_argument(
        "--base-url", default="http://banking.local", help="Base URL of the API")
    parser.add_argument(
        "--scenario", choices=["auth", "account", "transfer", "all"], default="all", help="Endpoint to test")
    parser.add_argument("--users", type=int, default=20,
                        help="Number of dummy users to generate")
    parser.add_argument("--rps", type=int, default=50,
                        help="Target Requests Per Second")
    parser.add_argument("--duration", type=int, default=60,
                        help="Duration of test in seconds")
    parser.add_argument("--workers", type=int, default=10,
                        help="Number of concurrent workers")
    args = parser.parse_args()

    # 1. Setup users
    users = setup_users(args.base_url, args.users)
    if not users:
        print("[-] Could not create any users. Exiting.")
        sys.exit(1)

    # 2. Run load test
    try:
        asyncio.run(run_load_test(args.base_url, users,
                    args.scenario, args.duration, args.rps, args.workers))
    except KeyboardInterrupt:
        print("\n[-] Load test aborted by user.")


if __name__ == "__main__":
    main()
