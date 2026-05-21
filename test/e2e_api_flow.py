import argparse
import time

import requests


def req(base_url: str, method: str, path: str, **kwargs) -> requests.Response:
    return requests.request(method, base_url + path, timeout=25, **kwargs)


def assert_notification_message(msg: str, role: str) -> None:
    lowered = (msg or "").lower()
    if role == "sender":
        ok = ("you sent" in lowered) or ("ban da chuyen" in lowered) or ("bạn đã chuyển" in lowered)
    else:
        ok = ("you received" in lowered) or ("ban nhan" in lowered) or ("bạn nhận" in lowered)
    assert ok, f"{role} notification unexpected: {msg}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://localhost:8000")
    args = parser.parse_args()
    base_url = args.base_url.rstrip("/")

    suffix = str(int(time.time()))[-8:]
    phone1 = f"09{suffix}01"
    phone2 = f"09{suffix}02"
    user1 = f"ci_user1_{suffix}"
    user2 = f"ci_user2_{suffix}"

    for phone, username in ((phone1, user1), (phone2, user2)):
        r = req(
            base_url,
            "POST",
            "/api/auth/register",
            json={"phone": phone, "username": username, "password": "123456"},
        )
        if r.status_code not in (200, 409):
            raise SystemExit(f"register failed: {r.status_code} {r.text}")

    login1 = req(base_url, "POST", "/api/auth/login", json={"phone": phone1, "password": "123456"})
    login2 = req(base_url, "POST", "/api/auth/login", json={"phone": phone2, "password": "123456"})
    assert login1.status_code == 200, f"login1 failed: {login1.status_code} {login1.text}"
    assert login2.status_code == 200, f"login2 failed: {login2.status_code} {login2.text}"

    s1 = login1.json()["session"]
    s2 = login2.json()["session"]
    h1 = {"X-Session": s1}
    h2 = {"X-Session": s2}

    me1_before = req(base_url, "GET", "/api/account/me", headers=h1)
    me2_before = req(base_url, "GET", "/api/account/me", headers=h2)
    assert me1_before.status_code == 200, f"me1 before failed: {me1_before.status_code} {me1_before.text}"
    assert me2_before.status_code == 200, f"me2 before failed: {me2_before.status_code} {me2_before.text}"
    u1_before = me1_before.json()
    u2_before = me2_before.json()

    transfer = req(
        base_url,
        "POST",
        "/api/transfer/transfer",
        headers=h1,
        json={"to_account_number": u2_before["account_number"], "amount": 1000},
    )
    assert transfer.status_code == 200, f"transfer failed: {transfer.status_code} {transfer.text}"

    me1_after = req(base_url, "GET", "/api/account/me", headers=h1).json()
    me2_after = req(base_url, "GET", "/api/account/me", headers=h2).json()
    assert me1_after["balance"] == u1_before["balance"] - 1000, (
        f"sender balance mismatch: {u1_before['balance']} -> {me1_after['balance']}"
    )
    assert me2_after["balance"] == u2_before["balance"] + 1000, (
        f"receiver balance mismatch: {u2_before['balance']} -> {me2_after['balance']}"
    )

    notif1 = req(base_url, "GET", "/api/notifications/notifications", headers=h1)
    notif2 = req(base_url, "GET", "/api/notifications/notifications", headers=h2)
    assert notif1.status_code == 200, f"notif1 failed: {notif1.status_code} {notif1.text}"
    assert notif2.status_code == 200, f"notif2 failed: {notif2.status_code} {notif2.text}"

    msg1 = (notif1.json() or [{}])[0].get("message", "")
    msg2 = (notif2.json() or [{}])[0].get("message", "")
    assert_notification_message(msg1, "sender")
    assert_notification_message(msg2, "receiver")

    print("E2E OK: transfer updated balances and notifications are present.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
