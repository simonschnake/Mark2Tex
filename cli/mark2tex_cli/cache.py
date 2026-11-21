"""Build artifacts and recorder-based cache validation."""

import filecmp
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import zipfile
import zlib

TEMP_PREFIX = ".mark2tex-"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def publish(source, destination, current=lambda: True):
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=TEMP_PREFIX, delete=False) as stream:
        temporary = Path(stream.name)
    try:
        shutil.copyfile(source, temporary)
        if current():
            os.replace(temporary, destination)
            return True
        return False
    finally:
        temporary.unlink(missing_ok=True)


def save_font_cache(source, directory):
    """Publish font cache files atomically so parallel builds can share them."""
    for path in source.rglob("*"):
        if path.is_file() and not path.is_symlink():
            target = directory / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.is_file() or not filecmp.cmp(path, target, shallow=False):
                publish(path, target)


def recorded_inputs(recorder, started):
    """Record external inputs, including files opened only on the first pass."""
    lines = recorder.read_text(encoding="utf-8", errors="replace").splitlines()
    directory = Path(next(line[4:] for line in lines if line.startswith("PWD ")))
    paths = {Path(os.path.abspath(directory / line[6:]))
             for line in lines if line.startswith("INPUT ")}
    inputs = {}
    for path in sorted(paths):
        if path.is_relative_to(directory) or not path.is_file():
            continue
        inputs[str(path)] = digest(path)
        if path.stat().st_ctime_ns > started:
            raise OSError(f"input changed during compilation: {path}")
    return inputs


def restore(entry, build, names):
    try:
        with zipfile.ZipFile(entry) as archive:
            inputs = json.loads(archive.read("inputs.json"))
            if any(digest(Path(path)) != expected for path, expected in inputs.items()):
                return None
            for name in names:
                (build / name).write_bytes(archive.read(name))
            return inputs
    except (OSError, ValueError, KeyError, TypeError, AttributeError,
            zipfile.BadZipFile, zlib.error):
        return None


def save(entry, build, names, inputs):
    package = build / (entry.parent.name + ".zip")
    with zipfile.ZipFile(package, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("inputs.json", json.dumps(inputs))
        for name in names:
            archive.write(build / name, name)
    entry.parent.mkdir(parents=True, exist_ok=True)
    publish(package, entry)
