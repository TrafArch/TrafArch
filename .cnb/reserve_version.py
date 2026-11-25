"""Reserve a versionCode while the CNB job holds the repository-wide lock."""

import json
import os
import re
from pathlib import Path
from urllib.request import Request, urlopen


# Shared by all TrafArch branches, including shallow checkouts on the runner.
ROOT_COMMIT = "9a6a6736d74aed6de177e256a933f7e87001dd70"
COUNTER = "trafarch-android-last-version-code"


def reserve(pubspec, exchange):
    data = pubspec.read_bytes()
    match = re.search(rb"^version:[ \t]*[^\s+]+\+([0-9]+)[ \t]*\r?$", data, re.MULTILINE)
    if not match:
        raise ValueError("Expected version: name+number in pubspec.yaml")
    rows = exchange()
    if not isinstance(rows, list):
        raise ValueError("Expected a list of CNB commit annotations")
    previous = next((row["value"] for row in rows if row["key"] == COUNTER), "0")
    if not re.fullmatch(r"[0-9]+", previous):
        raise ValueError("Invalid CNB version counter")
    code = max(int(match[1]), int(previous) + 1)
    if not 1 <= code <= 2_100_000_000:
        raise ValueError("Android versionCode is outside its supported range")
    exchange({"annotations": [{"key": COUNTER, "value": str(code)}]})
    pubspec.write_bytes(data[:match.start(1)] + str(code).encode("ascii") + data[match.end(1):])
    return code


def commit_annotations(data=None):
    url = (f"{os.environ['CNB_API_ENDPOINT'].rstrip('/')}/{os.environ['CNB_REPO_SLUG']}"
           f"/-/git/commit-annotations/{ROOT_COMMIT}")
    req = Request(url, headers={
        "Authorization": "Bearer " + os.environ["CNB_TOKEN"],
        "Accept": "application/json",
        "Content-Type": "application/json",
    }, method="GET" if data is None else "PUT",
        data=None if data is None else json.dumps(data).encode())
    with urlopen(req, timeout=20) as response:
        if data is None:
            return json.load(response)


if __name__ == "__main__":
    print("Android versionCode =", reserve(Path("pubspec.yaml"), commit_annotations))
