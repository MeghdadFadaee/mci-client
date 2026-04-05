from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Optional

import requests


class DotEnvStore:
    """
    Minimal .env reader/writer that preserves non-key lines.
    """

    _key_pattern = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=")

    def __init__(self, path: str | Path = ".env") -> None:
        self.path = Path(path)
        self.lines: list[str] = []
        self.data: dict[str, str] = {}
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            self.lines = []
            self.data = {}
            return

        self.lines = self.path.read_text(encoding="utf-8").splitlines()

        for line in self.lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            self.data[key] = self._unquote(value)

    @staticmethod
    def _unquote(value: str) -> str:
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            return value[1:-1]
        return value

    @staticmethod
    def _quote(value: str) -> str:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

    def get(self, key: str, default: Optional[str] = None) -> Optional[str]:
        return self.data.get(key, default)

    def set(self, key: str, value: Optional[str]) -> None:
        self.data[key] = "" if value is None else str(value)

    def save(self) -> None:
        existing_keys: set[str] = set()
        new_lines: list[str] = []

        for line in self.lines:
            match = self._key_pattern.match(line)
            if match:
                key = match.group(1)
                if key in self.data:
                    new_lines.append(f"{key}={self._quote(self.data[key])}")
                    existing_keys.add(key)
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)

        for key, value in self.data.items():
            if key not in existing_keys:
                new_lines.append(f"{key}={self._quote(value)}")

        self.path.write_text("\n".join(new_lines).rstrip() + "\n", encoding="utf-8")


class MCIInternetClient:
    AUTH_URL = "https://my.mci.ir/api/idm/v1/auth"
    PACKAGES_URL = "https://my.mci.ir/api/unit/v1/packages/details"

    def __init__(self, env_path: str | Path = ".env") -> None:
        self.env = DotEnvStore(env_path)
        self.session = requests.Session()

        """
        """
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Origin": "https://my.mci.ir",
            "Referer": "https://my.mci.ir/",
            "platform": "WEB",
            "version": "1.29.0",
        })

        self.username = self._require_env("MCI_USERNAME")
        self.password = self._require_env("MCI_PASSWORD")

        self.access_token = self.env.get("MCI_ACCESS_TOKEN")
        self.refresh_token = self.env.get("MCI_REFRESH_TOKEN")
        self.session_state = self.env.get("MCI_SESSION_STATE")

        self.access_token_expires_at = self._safe_int(self.env.get("MCI_ACCESS_TOKEN_EXPIRES_AT"))
        self.refresh_token_expires_at = self._safe_int(self.env.get("MCI_REFRESH_TOKEN_EXPIRES_AT"))

    def _require_env(self, key: str) -> str:
        value = self.env.get(key)
        if not value:
            raise ValueError(f"Missing required environment variable: {key}")
        return value

    @staticmethod
    def _safe_int(value: Optional[str]) -> Optional[int]:
        if value is None or value == "":
            return None
        try:
            return int(value)
        except ValueError:
            return None

    @staticmethod
    def _now() -> int:
        return int(time.time())

    @staticmethod
    def _expiry_from_seconds(expires_in: Any, safety_buffer: int = 30) -> Optional[int]:
        try:
            return int(time.time()) + int(expires_in) - safety_buffer
        except (TypeError, ValueError):
            return None

    def _token_is_valid(self, expires_at: Optional[int]) -> bool:
        return expires_at is not None and expires_at > self._now()

    def _save_auth_to_env(self, payload: dict[str, Any]) -> None:
        self.access_token = payload.get("access_token", self.access_token)
        self.refresh_token = payload.get("refresh_token", self.refresh_token)
        self.session_state = payload.get("session_state", self.session_state)

        access_expires_at = self._expiry_from_seconds(payload.get("expires_in"))
        refresh_expires_at = self._expiry_from_seconds(payload.get("refresh_expires_in"))

        if access_expires_at is not None:
            self.access_token_expires_at = access_expires_at
        if refresh_expires_at is not None:
            self.refresh_token_expires_at = refresh_expires_at

        self.env.set("MCI_ACCESS_TOKEN", self.access_token)
        self.env.set("MCI_REFRESH_TOKEN", self.refresh_token)
        self.env.set("MCI_SESSION_STATE", self.session_state)
        self.env.set("MCI_ACCESS_TOKEN_EXPIRES_AT", str(self.access_token_expires_at or ""))
        self.env.set("MCI_REFRESH_TOKEN_EXPIRES_AT", str(self.refresh_token_expires_at or ""))
        self.env.save()

    def _auth_request(self, body: dict[str, Any], bearer_token: Optional[str] = None) -> dict[str, Any]:
        headers = {}
        if bearer_token:
            headers["Authorization"] = f"Bearer {bearer_token}"

        response = self.session.post(self.AUTH_URL, json=body, headers=headers, timeout=30)
        response.raise_for_status()
        payload = response.json()

        if not isinstance(payload, dict):
            raise RuntimeError("Unexpected auth response format.")

        return payload

    def login(self) -> dict[str, Any]:
        payload = self._auth_request(
            {
                "username": self.username,
                "credential": self.password,
                "credential_type": "PASSWORD",
            }
        )
        self._save_auth_to_env(payload)
        return payload

    def refresh(self) -> dict[str, Any]:
        if not self.refresh_token:
            return self.login()

        payload = self._auth_request(
            {
                "username": self.username,
                "credential_type": "REFRESH_TOKEN",
                "credential": self.refresh_token,
            },
            bearer_token=self.access_token,
        )
        self._save_auth_to_env(payload)
        return payload

    def ensure_token(self, force_refresh: bool = False) -> str:
        if not force_refresh and self.access_token and self._token_is_valid(self.access_token_expires_at):
            return self.access_token

        if self.refresh_token and (
            force_refresh or self._token_is_valid(self.refresh_token_expires_at) or self.access_token
        ):
            try:
                self.refresh()
                if self.access_token:
                    return self.access_token
            except requests.HTTPError:
                pass

        self.login()
        if not self.access_token:
            raise RuntimeError("Authentication failed: access token not available.")
        return self.access_token

    def _get_packages_details(self) -> dict[str, Any]:
        token = self.ensure_token()
        headers = {"Authorization": f"Bearer {token}"}
        response = self.session.get(self.PACKAGES_URL, headers=headers, timeout=30)

        if response.status_code == 401:
            token = self.ensure_token(force_refresh=True)
            headers["Authorization"] = f"Bearer {token}"
            response = self.session.get(self.PACKAGES_URL, headers=headers, timeout=30)

        response.raise_for_status()
        payload = response.json()

        if not isinstance(payload, dict):
            raise RuntimeError("Unexpected packages response format.")

        return payload

    def _collect_unused_amounts(self, data: Any) -> list[int]:
        results: list[int] = []

        def walk(node: Any) -> None:
            if isinstance(node, dict):
                for key, value in node.items():
                    if key == "unusedAmount":
                        parsed = self._to_int(value)
                        if parsed is not None:
                            results.append(parsed)
                    walk(value)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(data)
        return results

    @staticmethod
    def _to_int(value: Any) -> Optional[int]:
        if isinstance(value, bool):
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            cleaned = value.strip()
            try:
                if "." in cleaned:
                    return int(float(cleaned))
                return int(cleaned)
            except ValueError:
                return None
        return None

    def get_unused_amounts_bytes(self) -> list[int]:
        """
        Returns all unusedAmount values found in the response tree.
        """
        payload = self._get_packages_details()
        return self._collect_unused_amounts(payload)

    def get_packages_response(self) -> dict[str, Any]:
        """
        Returns the full packages response.
        """
        return self._get_packages_details()


if __name__ == "__main__":
    import json
    import traceback

    print("=== MCI Internet Client Test ===")

    try:
        client = MCIInternetClient(".env")

        # 1. Check existing tokens
        print("\n[1] Checking existing token status...")
        print(f"Access token exists: {bool(client.access_token)}")
        print(f"Refresh token exists: {bool(client.refresh_token)}")

        # 2. Force ensure token (this may refresh or login)
        print("\n[2] Ensuring valid token...")
        token = client.ensure_token()
        print(f"Token acquired: {token[:20]}...")

        # 3. Fetch raw packages response
        print("\n[3] Fetching packages details...")
        packages = client.get_packages_response()
        print("Packages fetched successfully.")

        # Pretty print (optional, truncate if too large)
        print("\n--- Raw Response (truncated) ---")
        print(json.dumps(packages, indent=2)[:300], '...')

        # 4. Extract unused amounts
        print("\n[4] Extracting unusedAmount values...")
        unused_amounts = client.get_unused_amounts_bytes()

        if not unused_amounts:
            print("No unusedAmount found!")
        else:
            print(f"Found {len(unused_amounts)} entries:")
            for i, val in enumerate(unused_amounts, 1):
                print(f"  {i}. {val} bytes (~{round(val / (1024 ** 3), 2)} GB)")

            total = sum(unused_amounts)
            print(f"\nTotal unused: {total} bytes (~{round(total / (1024 ** 3), 2)} GB)")

        print("\n=== TEST SUCCESS ===")

    except Exception as e:
        print("\n=== TEST FAILED ===")
        print(f"Error: {e}")
        print("\nTraceback:")
        traceback.print_exc()