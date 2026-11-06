"""Prepare and verify local release artifacts. Never uploads or installs anything."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/SuQingSearchEnhancement"
PUB = ROOT / "publishing"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def hashes(folder):
    return {p.relative_to(folder).as_posix(): sha(p)
            for p in sorted(folder.rglob("*")) if p.is_file()}


def archive_files(destination, files):
    with ZipFile(destination, "x", compression=ZIP_DEFLATED) as out:
        for path, name in files:
            out.write(path, name)
    with ZipFile(destination) as out:
        assert out.testzip() is None
        assert set(out.namelist()) == {name for _, name in files}
        for path, name in files:
            assert out.read(name) == path.read_bytes(), name
    return {"path": str(destination), "sha256": sha(destination),
            "members": len(files), "readback": "all members byte-matched"}


def main():
    project = read(ROOT / "project.json")
    validation = read(ROOT / "validation/result.json")
    workshop = read(PUB / "workshop.json")
    assert not project.get("cover_selection_pending"), "select and export the replacement cover before freezing release materials"
    assert not workshop.get("cover_selection_pending"), "cover revision is still pending"
    acceptance = project["gameplay_acceptance"]
    runtime = {"mods/SuQingSearchEnhancement/" + k: v for k, v in hashes(MOD).items()}
    logic = {k: v for k, v in runtime.items() if k.endswith(".lua")}
    assert validation["result"] == "PASS" and runtime == validation["runtime_sha256"]
    assert acceptance["status"] == "user_confirmed" and acceptance["runtime_lua_sha256"] == logic
    assert not workshop["publication_authorized"] and workshop["publishedfileid"] is None
    version = re.search(r"^modversion=(.+)$", (MOD / "42/mod.info").read_text(encoding="utf-8"), re.M).group(1).strip()
    assert version == project["version"] == workshop["version"]
    frozen = Path(project["receipt"]).parent
    assert frozen.resolve().is_relative_to((ROOT / "release").resolve())
    runtime_archive = Path(project["frozen_candidate"])
    runtime_receipt = read(Path(project["receipt"]))
    assert sha(runtime_archive) == runtime_receipt["archive_sha256"]
    assert runtime_receipt["version"] == version and runtime_receipt["mod_id"] == project["mod_id"]
    assert runtime_receipt["runtime_lua_sha256"] == logic
    assert runtime_receipt["gameplay_acceptance"] == acceptance
    with ZipFile(runtime_archive) as archive:
        assert archive.testzip() is None
        assert {name: hashlib.sha256(archive.read(name)).hexdigest()
                for name in archive.namelist() if name.startswith("mods/")} == runtime
    before_local = hashes(Path(project["local_installation"]))
    local_logic = {"mods/SuQingSearchEnhancement/" + k: v for k, v in before_local.items() if k.endswith(".lua")}
    assert logic == local_logic, "release logic differs from user-tested personal installation"

    stage = frozen / "workshop-upload/SuQingSearchEnhancement"
    stage.mkdir(parents=True, exist_ok=False)
    shutil.copytree(MOD, stage / "Contents/mods/SuQingSearchEnhancement")
    shutil.copy2(PUB / "preview.png", stage / "preview.png")
    description = (PUB / "description.bbcode.txt").read_text(encoding="utf-8")
    metadata = ["version=1", "title=" + workshop["title"]]
    metadata.extend("description=" + line for line in description.splitlines())
    metadata += ["tags=" + ";".join(workshop["tags"]), "visibility=" + workshop["visibility"]]
    (stage / "workshop.txt").write_text("\n".join(metadata) + "\n", encoding="utf-8")
    assert hashes(stage / "Contents/mods/SuQingSearchEnhancement") == hashes(MOD)
    assert sha(stage / "preview.png") == sha(PUB / "preview.png")
    txt = (stage / "workshop.txt").read_text(encoding="utf-8")
    assert not re.search(r"^id=", txt, re.M)
    assert "\n".join(line.removeprefix("description=") for line in txt.splitlines()
                      if line.startswith("description=")) == description.rstrip("\n")
    upload_archive = archive_files(frozen / ("SuQingSearchEnhancement-" + version + "-workshop-ready.zip"),
        [(p, "SuQingSearchEnhancement/" + p.relative_to(stage).as_posix())
         for p in sorted(stage.rglob("*")) if p.is_file()])

    project.update({"state": "user-confirmed single-player logic; release materials ready locally; not uploaded",
                    "workshop": "prepared locally; not uploaded", "publication_authorized": False,
                    "local_installed_version": re.search(r"^modversion=(.+)$", (Path(project["local_installation"]) / "42/mod.info").read_text(encoding="utf-8"), re.M).group(1).strip(),
                    "workshop_staging": str(stage), "release_manifest": str(frozen / "release-manifest.json"),
                    "release_report": str(PUB / "待统一发布.md")})
    write_json(ROOT / "project.json", project)
    workshop.update({"prepared_at": datetime.now().astimezone().isoformat(),
                     "status": "prepared_not_uploaded",
                     "local_upload_folder": str(stage), "runtime_archive": str(runtime_archive),
                     "upload_archive": upload_archive["path"]})
    write_json(PUB / "workshop.json", workshop)
    manifest = {"prepared_at": datetime.now().astimezone().isoformat(), "version": version,
                "mod_id": project["mod_id"], "state": "prepared_not_uploaded",
                "publication_authorized": False, "uploaded": False, "workshop_item_id": None,
                "runtime_archive": {"path": str(runtime_archive), "sha256": sha(runtime_archive),
                                    "members": runtime_receipt["archive_members"], "readback": "all members byte-matched"},
                "upload_archive": upload_archive, "workshop_upload_folder": str(stage),
                "runtime_sha256": runtime, "runtime_lua_sha256": logic,
                "tested_logic_byte_identical": True, "gameplay_acceptance": acceptance,
                "offline_assertions": validation["assertions"], "art_check": read(PUB / "art-check.json"),
                "selected_cover": project.get("selected_cover"),
                "personal_installation_modified": False, "enabled_lists_modified": False,
                "game_configuration_modified": False, "git_commit_or_push_performed": False,
                "local_installation_sha256_before": before_local,
                "workshop_staging_sha256": hashes(stage)}

    report = f"""# 蘇清的搜索增强：待统一发布

准备时间：{manifest['prepared_at']}。版本 **{version}**，Mod ID `SuQingSearchEnhancement`。

用户已反馈当前本机 B42.21 单人配置中功能测试正常。冻结包的 8 个功能 Lua 文件与已测 0.1.0-rc.3 以及个人安装逐字节一致；本轮更新版本元数据、说明、用户选定的封面及本地发布材料。离线回归 {validation['assertions']} 条断言通过，中英资源与图片检查通过。英文完整游戏验收、其他版本、全部模组组合、多人及性能改善不在已确认范围。

## 发布材料

- 已核对系列封面、512×512 poster／预览，以及独立透明 128×128 icon；32／64／128 像素实际查看通过，无需重做。封面没有游戏版本文字。详见 `美术检查.md`。
- 当前选定封面：`{project.get('selected_cover', {}).get('path', 'see art/provenance.json')}`。旧图与候选保留；新冻结包使用用户选定稿，icon 保持不变。
- `title.txt`、`description.bbcode.txt`、`changenote.txt`：中英标题、介绍和更新说明。
- `dependencies.json`：核心无外部硬前置，拼音搜索／CleanUI／Proximity Inventory 均为可选。
- `workshop.json`：本地状态 `prepared_not_uploaded`，没有分配工坊 ID。没有进行线上查询或上传。
- 手动安装冻结包：`{runtime_archive}`。
- 工坊资料包：`{upload_archive['path']}`。
- 可供后续游戏原生上传器使用的目录：`{stage}`。只有 `Contents/mods/SuQingSearchEnhancement`、`preview.png` 和 `workshop.txt`，不含开发工具、个人备份或上游词典。
- 完整交付哈希与读回结果：`{frozen / 'release-manifest.json'}`。

## 当前安装与范围

个人安装仍为 **{project['local_installed_version']}**：`{project['local_installation']}`。本次未部署新版元数据，未改游戏配置、存档、启用名单和顺序，也未提交或推送 Git。发布代码与现用功能逻辑完全相同。

已知范围：高亮和置顶适配详细列表，图标网格未适配；原搜索框适配 CleanUI 2.10.4。只搜索界面已列出的随身物品、可访问且已探索的附近容器及可见地面。拼音取决于启用的上游组件及词典。查询仅存于会话。

## 后续统一发布入口

本次授权在“准备齐全”结束，**没有创建工坊物品，也没有上传任何内容（包括私密上传）**。本地 `workshop.txt` 的 private 仅为草稿默认值，不代表已发布；公开范围留到用户之后统一发布时决定。后续先复核目标游戏及依赖版本、冻结包哈希和是否已有工坊 ID，再按统一发布指令操作；可选项目不要设成硬性前置。若需要同时替换个人安装，应在游戏正常退出后单独完成，保留当前名单与配置。

原 rc.3 冻结包和历史部署收据保留。本次未覆盖个人运行文件，因此无需回滚游戏环境；需要撤回本次候选时只处理该新版本目录与源码元数据，不运行旧部署回滚脚本。
"""
    (PUB / "待统一发布.md").write_text(report, encoding="utf-8")

    source_paths = [ROOT / name for name in ("README.md", "README.en.md", "CHANGELOG.md", ".gitignore", "project.json")]
    for directory, suffixes in ((MOD, None), (ROOT / "tests", {".lua"}),
                                (ROOT / "tools", {".py", ".java"}), (ROOT / "art", {".png", ".json"}),
                                (PUB, {".txt", ".json", ".png", ".md"})):
        source_paths.extend(p for p in directory.rglob("*") if p.is_file()
                            and "__pycache__" not in p.parts and (suffixes is None or p.suffix in suffixes))
    source_paths += [ROOT / "validation/result.json"] + sorted((ROOT / "validation").glob("*.log"))
    source_archive = archive_files(frozen / ("SuQingSearchEnhancement-" + version + "-source.zip"),
        [(p, p.relative_to(ROOT).as_posix()) for p in sorted(set(source_paths))])
    manifest["source_archive"] = source_archive
    assert hashes(Path(project["local_installation"])) == before_local
    manifest["local_installation_sha256_after"] = before_local
    write_json(frozen / "release-manifest.json", manifest)
    print(json.dumps({"report": str(PUB / "待统一发布.md"), "runtime_archive": str(runtime_archive),
                      "workshop_upload_folder": str(stage), "upload_archive": upload_archive,
                      "source_archive": source_archive, "uploaded": False}, ensure_ascii=False))


if __name__ == "__main__":
    status_paths = [ROOT / "project.json", PUB / "workshop.json", PUB / "待统一发布.md"]
    original_status = {path: path.read_bytes() if path.exists() else None for path in status_paths}
    try:
        main()
    except Exception:
        # Keep partial artifacts for inspection, but never leave a failed attempt
        # claiming a newer completed release state.
        for path, original in original_status.items():
            if original is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(original)
        raise
