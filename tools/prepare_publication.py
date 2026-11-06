"""Freeze publication text/assets without installing, starting PZ or calling Steam.

Use --baseline-stage to bind runtime files to an already reviewed native package.
Each run creates a new release directory; existing freezes are never overwritten.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
import hashlib
import json
import re
import shutil
from PIL import Image
from workshop_identity import resolve_workshop_item, native_item_id_lines

ROOT = Path(__file__).resolve().parents[1]
PUB = ROOT / 'publishing'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(folder):
    return {p.relative_to(folder).as_posix(): {'bytes': p.stat().st_size, 'sha256': sha(p)}
            for p in sorted(folder.rglob('*')) if p.is_file()}


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def archive(path, files):
    assert not path.exists(), f'Refuse to overwrite {path}'
    names = [name for _, name in files]
    assert len(set(names)) == len(names)
    with ZipFile(path, 'x', ZIP_DEFLATED, compresslevel=9) as out:
        for source, name in files:
            out.write(source, name)
    with ZipFile(path) as check:
        assert check.testzip() is None
        assert set(check.namelist()) == set(names)
        for source, name in files:
            assert check.read(name) == source.read_bytes(), name
    return {'path': str(path), 'sha256': sha(path), 'members': len(names),
            'readback': 'CRC and all member bytes matched'}


def validate_translations(mod):
    base = mod / '42/media/lua/shared/Translate'
    folders = {lang: base / lang for lang in ['CN', 'EN']}
    sets = {lang: {p.name for p in folder.glob('*.json')} for lang, folder in folders.items()}
    assert sets['CN'] == sets['EN'] and sets['EN']
    count = 0
    for name in sorted(sets['EN']):
        cn, en = [read(folders[lang] / name) for lang in ['CN', 'EN']]
        assert set(cn) == set(en), name
        for key in en:
            assert sorted(re.findall(r'%\d+', cn[key])) == sorted(re.findall(r'%\d+', en[key])), key
        count += len(en)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-stage', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    stamp = datetime.now(timezone(timedelta(hours=8)))
    search = (ROOT / 'project.json').exists()
    metadata = read(PUB / ('workshop.json' if search else 'release-config.json'))
    mod_roots = [p for p in (ROOT / 'mods').iterdir() if p.is_dir()]
    assert len(mod_roots) == 1
    mod = mod_roots[0]
    info = dict(line.split('=', 1) for line in (mod / '42/mod.info').read_text(encoding='utf-8-sig').splitlines() if '=' in line)
    mid, version = info['id'], info['modversion']
    assert mod.name == mid and version == metadata['version']
    assert not info.get('require', '').strip(), 'This main mod currently has no hard prerequisite; review unexpected change'
    item_id = resolve_workshop_item(PUB, mid, metadata)
    visibility = metadata.get('visibility')
    assert visibility in {'private', 'public'}, 'Review unsupported visibility before preparing publication'
    # New items remain private drafts. Existing items can retain a public
    # choice already recorded by native readback, without changing Steam here.
    assert visibility == 'private' or item_id is not None, 'New-item preparation must remain private'
    baseline = args.baseline_stage.resolve()
    baseline_mod = baseline / 'Contents/mods' / mid
    assert baseline_mod.is_dir()
    runtime_before = hashes(mod)
    baseline_before = hashes(baseline)
    prior = hashes(baseline_mod)
    allowed_exports = {'42/poster.png', 'README.md', 'README.en.md'} if not search else set()
    assert all(item == prior.get(name) for name, item in runtime_before.items() if name not in allowed_exports), 'Runtime differs from reviewed baseline'
    assert not (set(prior) - set(runtime_before) - allowed_exports), 'Unexpected previous packaged runtime'
    translation_keys = validate_translations(mod)
    description = (PUB / ('description.bbcode.txt' if search else 'WorkshopDescription.CN_EN.bbcode.txt')).read_text(encoding='utf-8-sig')
    title = metadata['title'].strip()
    assert 0 < len(description.encode('utf-8')) < 8000 and '\0' not in description
    assert 0 < len(title.encode('utf-8')) <= 128 and not re.search(r'[\r\n\0]', title)
    if not search:
        assert metadata['description_utf8_bytes'] == len(description.encode('utf-8'))
        assert metadata['cn'] == (PUB / 'WorkshopDescription.CN.bbcode.txt').read_text(encoding='utf-8-sig')
        assert metadata['en'] == (PUB / 'WorkshopDescription.EN.bbcode.txt').read_text(encoding='utf-8-sig')
        sandbox = (mod / '42/media/sandbox-options.txt').read_text(encoding='utf-8-sig')
        time_options = [b for b in sandbox.split('option ')[1:] if re.search(r'(?i)hour|time', b.split('{', 1)[0])]
        assert time_options and all(re.search(r'default\s*=\s*10(?:\.0)?\s*,', b.split('}', 1)[0]) for b in time_options), 'Public restoration default must remain 10 game hours'
    for name in ['preview.png']:
        path = PUB / name
        with Image.open(path) as im:
            assert im.format == 'PNG' and im.size == (512, 512)
        assert path.stat().st_size < 1_000_000
        assert sha(path) == sha(baseline / name), 'Selected cover export changed'
    assert sha(mod / '42/icon.png') == sha(baseline_mod / '42/icon.png'), 'Selected independent icon changed'
    out = args.output or ROOT / 'release' / (version + '_' + stamp.strftime('%Y%m%d_%H%M%S') + '_publication-repair')
    out = out.resolve()
    assert out.is_relative_to((ROOT / 'release').resolve()) and not out.exists()
    out.mkdir(parents=True)
    stage = out / 'workshop-upload' / mid
    frozen_mod = stage / 'Contents/mods' / mid
    shutil.copytree(mod, frozen_mod)
    if not search:
        shutil.copy2(PUB / 'preview.png', frozen_mod / '42/poster.png')
        for lang, name in [('CN', 'README.md'), ('EN', 'README.en.md')]:
            shutil.copy2(PUB / f'README.public.{lang}.md', frozen_mod / name)
    shutil.copy2(PUB / 'preview.png', stage / 'preview.png')
    lines = ['version=1'] + native_item_id_lines(item_id) + ['title=' + title]
    lines += ['description=' + line for line in description.splitlines()]
    lines += ['tags=' + ';'.join(metadata['tags']), 'visibility=' + visibility]
    (stage / 'workshop.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    native_text = (stage / 'workshop.txt').read_text(encoding='utf-8')
    assert '\n'.join(x[len('description='):] for x in native_text.splitlines() if x.startswith('description=')) == description.rstrip('\n')
    assert re.findall(r'(?m)^id=(.*)$', native_text) == ([] if item_id is None else [item_id])
    publication = out / 'publication'
    publication.mkdir()
    title_name = 'title.txt' if search else 'Title.txt'
    note_name = 'changenote.txt' if search else 'ReleaseNotes.CN_EN.txt'
    shutil.copy2(PUB / title_name, publication / 'title.txt')
    shutil.copy2(PUB / note_name, publication / 'changenote.txt')
    (publication / 'description.bbcode.txt').write_text(description, encoding='utf-8')
    if not search:
        for lang in ['CN', 'EN']:
            shutil.copy2(PUB / f'WorkshopDescription.{lang}.bbcode.txt', publication / f'description.{lang}.bbcode.txt')
    else:
        shutil.copy2(PUB / 'dependencies.json', publication / 'dependencies.json')
    upload_archive = archive(out / f'{mid}-{version}-workshop-ready.zip',
        [(p, mid + '/' + p.relative_to(stage).as_posix()) for p in sorted(stage.rglob('*')) if p.is_file()])
    manual_files = [(p, 'mods/' + mid + '/' + p.relative_to(frozen_mod).as_posix()) for p in sorted(frozen_mod.rglob('*')) if p.is_file()]
    if search:
        # Keep the existing manual-package contract: installable mods plus the
        # bilingual instructions and changelog alongside the mods directory.
        manual_files += [(ROOT / name, name) for name in ['README.md', 'README.en.md', 'CHANGELOG.md']]
    runtime_archive = archive(out / f'{mid}-{version}-manual.zip', manual_files)
    frozen_runtime = hashes(frozen_mod)
    differences = {name: {'source': runtime_before.get(name), 'frozen': frozen_runtime.get(name)}
                   for name in sorted(set(runtime_before) | set(frozen_runtime)) if runtime_before.get(name) != frozen_runtime.get(name)}
    assert set(differences) <= allowed_exports
    assert hashes(mod) == runtime_before and hashes(baseline) == baseline_before
    manifest = {'schema_version': 1, 'prepared_at_bjt': stamp.isoformat(), 'mod_id': mid, 'version': version,
                'state': 'prepared_not_uploaded', 'publication_authorized': False, 'uploaded': False,
                'workshop_item_id': item_id, 'workshop_upload_folder': str(stage),
                'content_path': str(stage / 'Contents'), 'title_file': str(publication / 'title.txt'),
                'description_file': str(publication / 'description.bbcode.txt'),
                'changenote_file': str(publication / 'changenote.txt'), 'preview_file': str(stage / 'preview.png'),
                'description_utf8_bytes': len(description.encode('utf-8')), 'required_workshop_ids': [],
                'runtime_source_sha256': runtime_before, 'runtime_frozen_sha256': frozen_runtime,
                'workshop_staging_sha256': hashes(stage), 'publication_sha256': hashes(publication),
                'runtime_archive': runtime_archive, 'upload_archive': upload_archive,
                'baseline_stage': str(baseline), 'baseline_runtime_byte_match_except_expected_exports': True,
                'expected_runtime_exports': differences, 'translation_key_count': translation_keys,
                'runtime_logic_changed': False, 'selected_art_unchanged': True,
                'personal_installation_modified': False, 'enabled_lists_modified': False,
                'game_configuration_modified': False, 'git_commit_or_push_performed': False,
                'gameplay_tested_by_this_operation': False,
                'remaining_acceptance': read(ROOT / 'project.json')['gameplay_acceptance']['not_claimed'] if search else
                    (['PZO display with enabled/unknown rotten-food removal, Viewpoint visuals/collision, multiplayer'] if mid.endswith('Fridge') else
                     ['rc.5 ground outline rotation/placement/Viewpoint; full new container integration acceptance; multiplayer']),
                'checks': ['native fields read back', 'description/title bytes', 'real PNG dimensions and preview limit',
                           'reviewed runtime baseline binding', 'CN/EN JSON key and placeholder parity',
                           'public 10-hour freshness default' if not search else 'user-confirmed Lua unchanged',
                           'both archives CRC/membership/all bytes', 'baseline and source runtime unchanged']}
    save(out / 'release-manifest.json', manifest)
    pointer = {'prepared_at_bjt': stamp.isoformat(), 'mod_id': mid, 'version': version,
               'release_manifest': str(out / 'release-manifest.json'), 'workshop_upload_folder': str(stage),
               'workshop_item_id': item_id,
               'uploaded': False, 'git_committed_or_pushed': False, 'description_utf8_bytes': manifest['description_utf8_bytes']}
    save(PUB / 'latest-preparation.json', pointer)
    print(json.dumps(pointer, ensure_ascii=False))


if __name__ == '__main__':
    main()
