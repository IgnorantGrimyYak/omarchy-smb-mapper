#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=$project_dir/bin/smb-mapper
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

chmod +x "$helper"

export OMARCHY_SMB_TEST=1
export OMARCHY_SMB_CONFIG_DIR=$fixture_dir/config
export OMARCHY_SMB_SHARES_DIR=$fixture_dir/Shares
export OMARCHY_SMB_RUNTIME_DIR=$fixture_dir/runtime
export HOME=$fixture_dir

fail() { printf 'helper test failed: %s\n' "$*" >&2; exit 1; }

run() {
  local stdin=${1:-}
  shift
  if [[ -n $stdin ]]; then
    printf '%s\n' "$stdin" | python3 "$helper" "$@"
  else
    python3 "$helper" "$@"
  fi
}

json_ok() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); assert data.get("ok") is True, data; print(json.dumps(data))'
}

out=$(run '{"host":"nas.local","share":"media","username":"bryan","password":"s3cret","label":"NAS","automount":true}' add)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["ok"] and data["share"]["label"]=="NAS" and data["share"]["hasSecret"] and "password" not in data["share"]' "$out" || fail "add did not store a public share"

python3 - <<'PY' || fail "password leaked into shares.json"
import json, os, pathlib, stat
path = pathlib.Path(os.environ["OMARCHY_SMB_CONFIG_DIR"]) / "shares.json"
text = path.read_text()
assert "s3cret" not in text
mode = path.stat().st_mode
assert stat.S_IMODE(mode) == 0o600, oct(mode)
data = json.loads(text)
assert data["shares"][0]["host"] == "nas.local"
assert "password" not in data["shares"][0]
PY

share_id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["share"]["id"])' "$out")

listed=$(run '' list | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["shares"][0]["mounted"] is False' "$listed" || fail "new share should start unmounted"

mounted=$(run '' mount "$share_id" | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["share"]["mounted"] is True' "$mounted" || fail "mount failed"

link=$OMARCHY_SMB_SHARES_DIR/NAS
[[ -L $link ]] || fail "expected convenience symlink in Shares"

unmounted=$(run '' unmount "$share_id" | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["share"]["mounted"] is False' "$unmounted" || fail "unmount failed"

auto=$(run '' automount | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert len(data["mounted"])==1' "$auto" || fail "automount did not remount the share"

if printf '%s\n' '{"host":"nas.local/evil","share":"media","username":"bryan","password":"x"}' | python3 "$helper" add >/dev/null 2>"$fixture_dir/invalid-host.err"; then
  fail "invalid host was accepted"
fi
grep -q 'hostname or IP' "$fixture_dir/invalid-host.err" || fail "invalid host error was unclear"

if printf '%s\n' '{"host":"nas.local","share":"../etc","username":"bryan","password":"x"}' | python3 "$helper" add >/dev/null 2>"$fixture_dir/invalid-share.err"; then
  fail "path-like share name was accepted"
fi
grep -q 'Share name is invalid' "$fixture_dir/invalid-share.err" || fail "invalid share error was unclear"

guest=$(run '{"host":"public.local","share":"open","guest":true,"label":"Public"}' add | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["share"]["guest"] is True and data["share"]["hasSecret"] is False' "$guest" || fail "guest share stored a secret"

removed=$(run '' remove "$share_id" | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data["ok"] is True' "$removed" || fail "remove failed"

listed=$(run '' list | json_ok)
python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert len(data["shares"])==1' "$listed" || fail "expected only the guest share to remain"

echo "helper tests passed"
