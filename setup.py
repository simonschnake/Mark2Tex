from pathlib import Path
import shutil

from setuptools import setup
from setuptools.command.build_py import build_py


class BuildWithTeX(build_py):
    """Package the same Lua and TeX sources used by the standalone archives."""

    def run(self):
        super().run()
        root = Path(__file__).resolve().parent
        destination = Path(self.build_lib) / "mark2tex_cli" / "tex"
        if destination.is_dir() and not self.dry_run:
            shutil.rmtree(destination)
        sources = [
            root / "mark2tex.lua", root / "mark2tex.sty",
            root / "scripts/convert.lua", *sorted(root.glob("src/mark2tex/*.lua")),
        ]
        for source in sources:
            target = destination / source.relative_to(root)
            self.mkpath(str(target.parent))
            self.copy_file(str(source), str(target))


setup(cmdclass={"build_py": BuildWithTeX})
