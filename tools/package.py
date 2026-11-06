"""Freeze a verified candidate and install or update its local runtime files."""
import argparse
import copy
from datetime import datetime
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/SuQingSearchEnhancement"
USER = Path(r"C:\Users\15792\Zomboid")
TARGET = USER / "mods/SuQingSearchEnhancement"
VERSION = re.search(r"^modversion=(.+)$", (MOD / "42/mod.info").read_text(encoding="utf-8"), re.M).group(1).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def runtime_lua_hashes():
    return {str(path.relative_to(ROOT)).replace("\\", "/"): digest(path)
            for path in sorted(MOD.rglob("*"))
            if path.is_file() and path.suffix.lower() == ".lua"}


def bound_gameplay_acceptance(project, logic_hashes):
    """Carry user acceptance across metadata changes, never across changed logic."""
    prior = project.get("gameplay_acceptance")
    confirmed = (bool(logic_hashes) and isinstance(prior, dict)
                 and prior.get("status") == "user_confirmed"
                 and prior.get("runtime_lua_sha256") == logic_hashes)
    if confirmed:
        return copy.deepcopy(prior), True
    reason = ("Runtime Lua files differ from the user-confirmed logic."
              if isinstance(prior, dict) and prior.get("status") == "user_confirmed"
              else "No user confirmation is bound to the current runtime Lua files.")
    return {"status": "pending_user_test", "runtime_lua_sha256": dict(logic_hashes),
            "reason": reason}, False


def protected_hashes():
    save_name, save_mode = (USER / "latestSave.ini").read_text(encoding="utf-8-sig").splitlines()[:2]
    save = USER / "Saves" / save_mode / save_name
    files = [USER / "latestSave.ini", USER / "options.ini", USER / "mods/default.txt",
             USER / "Lua/ModOptions.ini", save / "mods.txt", save / "map_sand.bin", save / "players.db"]
    return {str(path): digest(path) for path in files if path.exists()}


def check_game_exited():
    command = r"""Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^ProjectZomboid.*\.exe$' -or
        ($_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match '(?i)ProjectZomboid|zombie\.')
    } | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"""
    result = subprocess.run(["powershell", "-NoProfile", "-Command", command],
                            capture_output=True, text=True, check=True)
    if result.stdout.strip():
        raise RuntimeError("Game process detected; exit normally before installing")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-new", action="store_true")
    parser.add_argument("--update-existing", action="store_true")
    args = parser.parse_args()
    assert not (args.install_new and args.update_existing), "choose one installation operation"
    install = args.install_new or args.update_existing
    project_path = ROOT / "project.json"
    project = json.loads(project_path.read_text(encoding="utf-8")) if project_path.exists() else {}
    validation = json.loads((ROOT / "validation/result.json").read_text(encoding="utf-8"))
    assert validation["result"] == "PASS"
    for relative, expected in validation["runtime_sha256"].items():
        assert digest(ROOT / relative) == expected, "runtime changed since validation: " + relative
    current_files = {str(path.relative_to(ROOT)).replace("\\", "/")
                     for path in MOD.rglob("*") if path.is_file()}
    assert current_files == set(validation["runtime_sha256"]), "runtime file set changed"
    logic_hashes = runtime_lua_hashes()
    gameplay_acceptance, acceptance_preserved = bound_gameplay_acceptance(project, logic_hashes)
    if install:
        check_game_exited()
    if args.install_new:
        assert not TARGET.exists(), "refusing to overwrite an existing local installation"
    if args.update_existing:
        assert TARGET.is_dir(), "local installation is missing"
        assert TARGET.resolve() == TARGET.absolute(), "review a redirected installation before overwriting"
        installed_info = (TARGET / "42/mod.info").read_text(encoding="utf-8")
        assert re.search(r"^id=SuQingSearchEnhancement$", installed_info, re.M), "unexpected installation"
        expected_files = {path.relative_to(MOD) for path in MOD.rglob("*") if path.is_file()}
        assert all(path.relative_to(TARGET) in expected_files for path in TARGET.rglob("*") if path.is_file()), "unexpected local files require review"
    before = protected_hashes()
    timestamp = datetime.now().astimezone()
    frozen = ROOT / "release" / (VERSION + "_" + timestamp.strftime("%Y%m%d_%H%M%S"))
    frozen.mkdir(parents=True, exist_ok=False)
    archive = frozen / ("SuQingSearchEnhancement-" + VERSION + ".zip")
    payload = sorted(path for path in MOD.rglob("*") if path.is_file())
    payload.extend(ROOT / name for name in ("README.md", "README.en.md", "CHANGELOG.md"))
    with ZipFile(archive, "x", compression=ZIP_DEFLATED) as output:
        for path in payload:
            output.write(path, str(path.relative_to(ROOT)).replace("\\", "/"))
    with ZipFile(archive) as output:
        assert output.testzip() is None
        for path in payload:
            relative = str(path.relative_to(ROOT)).replace("\\", "/")
            assert output.read(relative) == path.read_bytes(), relative
        archived_logic_hashes = {
            name: hashlib.sha256(output.read(name)).hexdigest()
            for name in output.namelist()
            if name.startswith("mods/SuQingSearchEnhancement/") and Path(name).suffix.lower() == ".lua"
        }
        assert archived_logic_hashes == logic_hashes, "runtime Lua changed while freezing the candidate"
    previous_installation = None
    if args.update_existing:
        previous_installation = frozen / "previous-installation" / TARGET.name
        shutil.copytree(TARGET, previous_installation)
        for path in TARGET.rglob("*"):
            if path.is_file():
                assert digest(path) == digest(previous_installation / path.relative_to(TARGET)), str(path)
    if install:
        check_game_exited()
        try:
            shutil.copytree(MOD, TARGET, dirs_exist_ok=args.update_existing)
            for path in MOD.rglob("*"):
                if path.is_file():
                    assert digest(path) == digest(TARGET / path.relative_to(MOD)), str(path)
            assert sum(path.is_file() for path in TARGET.rglob("*")) == len(current_files)
        except Exception:
            if previous_installation:
                previous_files = {path.relative_to(previous_installation) for path in previous_installation.rglob("*") if path.is_file()}
                for path in MOD.rglob("*"):
                    if path.is_file() and path.relative_to(MOD) not in previous_files:
                        added = TARGET / path.relative_to(MOD)
                        assert added.resolve().is_relative_to(TARGET.resolve())
                        if added.is_file():
                            added.unlink()
                shutil.copytree(previous_installation, TARGET, dirs_exist_ok=True)
                for relative in previous_files:
                    assert digest(previous_installation / relative) == digest(TARGET / relative)
            raise
    after = protected_hashes()
    assert before == after, "protected files changed during packaging/install; inspect before continuing"
    operation = "update_existing" if args.update_existing else "install_new" if args.install_new else "freeze_only"
    if previous_installation:
        recovery = "With the game exited, restore this mod's runtime files from previous_installation_backup to return to the earlier version; remove only new files listed in this receipt. Keep save lists and unrelated settings current."
    elif install:
        recovery = "New standalone local mod folder installed. Disable this mod to end its UI behavior. No existing files were overwritten."
    else:
        recovery = "Frozen candidate only. This operation did not install or change local runtime files, save lists or settings. The candidate archive is available for a separately authorized installation."
    deployment_state = ("local runtime updated" if args.update_existing
                        else "new local runtime installed" if args.install_new
                        else "candidate frozen; local installation unchanged")
    acceptance_state = ("bound user gameplay confirmation retained" if acceptance_preserved
                        else "current runtime logic awaits user gameplay acceptance")
    receipt = {
        "version": VERSION, "created_at": timestamp.isoformat(), "source": str(ROOT),
        "mod_id": "SuQingSearchEnhancement", "game_target": "B42.21 single-player",
        "archive": str(archive), "archive_sha256": digest(archive),
        "archive_members": len(payload), "archive_readback": "all members matched",
        "operation": operation,
        "local_installation": str(TARGET) if install else None,
        "installation_files_verified": len(current_files) if install else 0,
        "previous_installation_backup": str(previous_installation) if previous_installation else None,
        "enabled_lists_modified": False, "workshop_uploaded": False,
        "offline_assertions": validation["assertions"],
        "in_game_acceptance": gameplay_acceptance["status"],
        "gameplay_acceptance": gameplay_acceptance,
        "runtime_lua_sha256": logic_hashes,
        "acceptance_binding_verified": acceptance_preserved,
        "protected_before": before, "protected_after": after,
        "recovery": recovery,
        "runtime_files": sorted(str(path.relative_to(MOD)).replace("\\", "/") for path in MOD.rglob("*") if path.is_file()),
    }
    (frozen / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    project.update({
        "title_cn": "蘇清的搜索增强", "title_en": "SuQing's Search Enhancement",
        "mod_id": "SuQingSearchEnhancement", "version": VERSION, "source": str(ROOT),
        "required_mods": [], "native_api": "PZAPI/ModOptions",
        "optional_integrations": ["CleanUI 2.10.4", "yxjs_PinYinSearch 1.3", "ProximityInventory"],
        "local_installation": receipt["local_installation"] or project.get("local_installation"),
        "frozen_candidate": str(archive), "receipt": str(frozen / "receipt.json"),
        "validation": str(ROOT / "validation/result.json"),
        "state": "offline passed; " + deployment_state + "; " + acceptance_state + "; Workshop not uploaded",
        "gameplay_acceptance": gameplay_acceptance,
        "workshop": "not uploaded", "git": "not committed or pushed"
    })
    project_path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: receipt[key] for key in (
        "archive", "archive_sha256", "archive_members", "local_installation",
        "installation_files_verified", "offline_assertions")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
