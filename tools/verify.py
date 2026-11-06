"""Offline checks using PZ's standalone compiler and mock regression suites."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MOD = ROOT / "mods/SuQingSearchEnhancement/42"
LUA = MOD / "media/lua"
TESTS = ROOT / "tests"
OUT = ROOT / "validation"
JAVAC = Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe")
JAVA = GAME / "jre64/bin/java.exe"
LAUNCHER = json.loads((GAME / "ProjectZomboid64.json").read_text(encoding="utf-8-sig"))
RUNTIME_CLASSPATH = [GAME / entry for entry in LAUNCHER["classpath"]]
CLASSPATH = ";".join(str(path) for path in [OUT, *RUNTIME_CLASSPATH])


def run(label, arguments):
    result = subprocess.run([str(part) for part in arguments], cwd=GAME,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode("utf-8", errors="replace")
    (OUT / (label + ".log")).write_text(output, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(label + " failed\n" + output[-4000:])
    print(label + " PASS")
    return output


def execute(label, files):
    return run(label, [JAVA, "--enable-native-access=ALL-UNNAMED", "-Dstdout.encoding=UTF-8", "-Duser.home=" + str(OUT / "isolated-home"),
                       "-cp", CLASSPATH, "LuaCheck", *files])


def lua_string(value):
    # PZ's LexState decodes its literal byte buffer as UTF-8. Decimal escapes
    # preserve generated dictionary data exactly as Java getText would return it.
    return '"' + "".join("\\" + str(byte).zfill(3) for byte in value.encode("utf-8")) + '"'


def cleanui_release_fixture():
    # This is an explicitly reviewed upstream fixture, not a generic CleanUI
    # compatibility claim. Re-review its handlers if the branch/version/hash
    # changes; failing here prevents a passing mock from masking upstream drift.
    branch = GAME.parent.parent / "workshop/content/108600/3437629766/mods/CleanUI/42.19"
    source = branch / "media/lua/client/ISUI/ISInventoryPane.lua"
    info = (branch / "mod.info").read_text(encoding="utf-8-sig")
    version = re.search(r"^modversion=(.+)$", info, re.MULTILINE).group(1).strip()
    assert version == "2.10.4", "CleanUI release fixture requires a new source review: version changed"
    raw = source.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    reviewed = "b0de68c2766c29ef26d001a20ba42e8fe17176b77eeaed1c73035b0e8e7ac06e"
    assert digest == reviewed, "CleanUI release fixture requires a new source review: upstream file changed"
    text = raw.decode("utf-8-sig")
    parts, methods = [], []
    boundaries = [
        ("onMouseDownOutside", "function ISInventoryPane:onMouseDownOutside(x, y)",
         "function ISInventoryPane:onMouseUpOutside(x, y)"),
        ("onMouseUpOutside", "function ISInventoryPane:onMouseUpOutside(x, y)",
         "function ISInventoryPane.getActualItems(items)"),
        ("onMouseUp", "function ISInventoryPane:onMouseUp(x, y)",
         "function ISInventoryPane:canPutIn()"),
    ]
    for name, start_marker, end_marker in boundaries:
        assert text.count(start_marker) == text.count(end_marker) == 1, "CleanUI release method boundary changed: " + name
        start, end = text.index(start_marker), text.index(end_marker)
        assert start < end, "CleanUI release method order changed: " + name
        body = text[start:end].rstrip()
        # An intervening top-level method would make this fixture ambiguous.
        assert len(re.findall(r"^function ", body, re.MULTILINE)) == 1, "CleanUI release fixture includes extra method: " + name
        assert body.endswith("end"), "CleanUI release method is incomplete: " + name
        parts.append(body)
        methods.append({"method": name, "start_line": text.count("\n", 0, start) + 1,
                        "end_line": text.count("\n", 0, start + len(body)) + 1,
                        "sha256": hashlib.sha256(body.encode("utf-8")).hexdigest()})
    fixture = OUT / "cleanui_release_fixture.lua"
    fixture.write_text("-- Generated from the reviewed current CleanUI source.\n"
                       "CleanUIReleaseFixture = true\n" + "\n\n".join(parts) + "\n", encoding="utf-8")
    return fixture, {"path": str(source), "branch": "42.19", "version": version, "sha256": digest,
                     "methods": methods, "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
                     "review_policy": "re-review branch, version and source hash before accepting upstream changes"}


def main():
    OUT.mkdir(exist_ok=True)
    run("java_compile", [JAVAC, "-encoding", "UTF-8", "-d", OUT,
                         ROOT / "tools/LuaCheck.java", ROOT / "tools/SandboxNativeProbe.java"])
    files = sorted(LUA.rglob("*.lua"))
    run("lua_compile", [JAVA, "-cp", CLASSPATH, "LuaCheck", "--compile", *files, *sorted(TESTS.glob("*.lua"))])
    core = LUA / "shared/SuQingSearch/Core.lua"
    text = LUA / "shared/SuQingSearch/Text.lua"
    runtime = LUA / "client/SuQingSearch/Runtime.lua"
    logs = {"core": execute("core", [core, TESTS / "core_tests.lua"])}
    logs["sandbox_native"] = run("sandbox_native", [JAVA, "--enable-native-access=ALL-UNNAMED",
                            "-Dstdout.encoding=UTF-8", "-Duser.home=" + str(OUT / "sandbox-probe-home"),
                            "-cp", CLASSPATH, "SandboxNativeProbe", MOD])
    # J2SEPlatform intentionally has no file IO/dofile. Inline the exact product
    # module at the two reload points, preserving the fixture's normal callbacks.
    integration = LUA / "client/SuQingSearch/Integration.lua"
    fixture = (TESTS / "integration_tests.lua").read_text(encoding="utf-8")
    loader = 'dofile("mods/SuQingSearchEnhancement/42/media/lua/client/SuQingSearch/Integration.lua")'
    assert fixture.count(loader) == 2, "integration fixture loader changed"
    bundle = OUT / "integration_bundle.lua"
    inline = "do\nlocal function loadIntegration()\n" + integration.read_text(encoding="utf-8") + "\nend\nloadIntegration()\nend"
    bundle.write_text(fixture.replace(loader, inline), encoding="utf-8")
    logs["integration"] = execute("integration", [core, bundle])
    logs["runtime"] = execute("runtime", [TESTS / "runtime_bootstrap.lua", text, core, runtime, TESTS / "runtime_tests.lua"])
    logs["panel"] = execute("panel", [TESTS / "runtime_bootstrap.lua", TESTS / "panel_bootstrap.lua",
                      GAME / "media/lua/client/PZAPI/ModOptions.lua", text, core,
                      LUA / "client/SuQingSearch/Settings.lua", runtime,
                      LUA / "client/SuQingSearch/Panel.lua", TESTS / "panel_tests.lua"])
    logs["settings"] = execute("settings", [TESTS / "runtime_bootstrap.lua", TESTS / "panel_bootstrap.lua",
                      GAME / "media/lua/client/PZAPI/ModOptions.lua", core,
                      LUA / "client/SuQingSearch/Settings.lua", TESTS / "settings_tests.lua"])
    interaction_patch = Path(r"C:\Users\15792\Zomboid\mods\SuQingUIInteractionFixes\42\media\lua\client\SuQing_ProximitySelectionFix.lua")
    logs["ordering"] = execute("ordering", [TESTS / "ordering_bootstrap.lua", interaction_patch,
                                           LUA / "client/SuQingSearch/Ordering.lua", TESTS / "ordering_tests.lua"])
    release_fixture, release_source = cleanui_release_fixture()
    logs["ordering_drag_release"] = execute("ordering_drag_release", [TESTS / "ordering_bootstrap.lua",
                     LUA / "client/SuQingSearch/Ordering.lua", release_fixture, TESTS / "ordering_drag_release_tests.lua"])
    pinyin_root = GAME.parent.parent / "workshop/content/108600/3657184750/mods/PinYinSearch/42.0/media/lua"
    pinyin_provider = pinyin_root / "client/pinyin.lua"
    pinyin_sources = {}
    for language in ("CN", "CH"):
        dictionary_path = pinyin_root / "shared/Translate" / language / "UI.json"
        dictionary = json.loads(dictionary_path.read_text(encoding="utf-8-sig"))
        entries = ["[" + lua_string(key) + "]=" + lua_string(value)
                   for key, value in dictionary.items()]
        dictionary_fixture = OUT / ("text_dictionary_" + language + ".lua")
        dictionary_fixture.write_text("SQTextTranslations={\n" + ",\n".join(entries) + "\n}\nSQTextTestLanguage=" + json.dumps(language) + "\n", encoding="utf-8")
        logs["text_" + language] = execute("text_" + language, [dictionary_fixture, TESTS / "text_bootstrap.lua",
                          text, pinyin_provider, TESTS / "text_tests.lua"])
        pinyin_sources[language] = {"path": str(dictionary_path), "sha256": hashlib.sha256(dictionary_path.read_bytes()).hexdigest()}
        if language == "CN":
            logs["pinyin_runtime"] = execute("pinyin_runtime", [TESTS / "runtime_bootstrap.lua", dictionary_fixture,
                        TESTS / "text_bootstrap.lua", text, pinyin_provider, core, runtime, TESTS / "pinyin_runtime_tests.lua"])

    translations = LUA / "shared/Translate"
    cn = json.loads((translations / "CN/UI.json").read_text(encoding="utf-8"))
    en = json.loads((translations / "EN/UI.json").read_text(encoding="utf-8"))
    assert cn.keys() == en.keys(), "translation key mismatch"
    for key in cn:
        assert re.findall(r"%\d+", cn[key]) == re.findall(r"%\d+", en[key]), key
    sandbox_cn = json.loads((translations / "CN/Sandbox.json").read_text(encoding="utf-8"))
    sandbox_en = json.loads((translations / "EN/Sandbox.json").read_text(encoding="utf-8"))
    assert sandbox_cn.keys() == sandbox_en.keys(), "sandbox translation key mismatch"
    for key in sandbox_cn:
        assert re.findall(r"%\d+", sandbox_cn[key]) == re.findall(r"%\d+", sandbox_en[key]), key
    referenced = set()
    for file in files:
        referenced.update(re.findall(r'["\x27](UI_SQSearch_\w+)["\x27]', file.read_text(encoding="utf-8")))
    assert referenced <= cn.keys(), "missing translations: " + str(referenced - cn.keys())
    for language in ("CN", "EN"):
        metadata = json.loads((translations / language / "Mod.json").read_text(encoding="utf-8"))
        assert metadata["name"] and metadata["description"]
    with Image.open(MOD / "poster.png") as image:
        assert image.format == "PNG" and image.size == (512, 512)
    with Image.open(MOD / "icon.png") as image:
        assert image.format == "PNG" and image.size == (128, 128)
        assert image.mode == "RGBA" and image.getchannel("A").getextrema() == (0, 255)
    hashes = {str(file.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(file.read_bytes()).hexdigest()
              for file in sorted(MOD.rglob("*")) if file.is_file()}
    regression = {}
    for name, log in logs.items():
        assertions = re.search(r"assertions=(\d+) failures=0", log)
        assert assertions, "missing regression result for " + name
        regression[name] = {"assertions": int(assertions.group(1))}
        cases = re.search(r"cases=(\d+)", log)
        if cases:
            regression[name]["cases"] = int(cases.group(1))
    summary = {"result": "PASS", "checked_at": datetime.now().astimezone().isoformat(),
               "game_version": re.search(r"NATIVE_GAME version=(.+)", logs["sandbox_native"]).group(1).strip(),
               "lua_product_files": len(files),
               "runtime_classpath": [{"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in RUNTIME_CLASSPATH],
               "regression": regression,
               "assertions": sum(item["assertions"] for item in regression.values()),
               "ordering_compatibility_source": {"path": str(interaction_patch),
                   "sha256": hashlib.sha256(interaction_patch.read_bytes()).hexdigest()},
               "ordering_drag_release_source": release_source,
               "pinyin_compatibility_sources": {"provider": {"path": str(pinyin_provider),
                   "sha256": hashlib.sha256(pinyin_provider.read_bytes()).hexdigest()}, "dictionaries": pinyin_sources},
               "bilingual_ui_keys": len(cn), "bilingual_sandbox_keys": len(sandbox_cn), "game_started": False,
               "gameplay_acceptance": "not evaluated by offline tests; see project.json gameplay_acceptance",
               "runtime_sha256": hashes}
    (OUT / "result.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("ALL OFFLINE CHECKS PASS")


if __name__ == "__main__":
    main()
