"""Compile Markdown with the bundled Mark2TeX converter and LuaLaTeX."""

import argparse
import hashlib
from importlib.metadata import PackageNotFoundError, version
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from . import cache

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE / "templates"
TEX = HERE / "tex" if (HERE / "tex").is_dir() else HERE.parents[1]
RUNTIME_BOUNDARY = "% mark2tex runtime\n"
BUILD_FILES = ("document.pdf", "document.log", "build.log")
FORMAT_FILE = "mark2tex-format.fmt"

FORMAT_BOOTSTRAP = r"""\let\MarkTwoTeXDump\dump
\let\dump\relax
\input lualatex.ini
\let\dump\MarkTwoTeXDump
\directlua{require('luaotfload-main');luaotfload.main()}
\makeatletter
\let\f@encoding\encodingdefault
\expandafter\let\csname ver@luaotfload.sty\endcsname\fmtversion
\makeatother
"""
FORMAT_RUNTIME = r"""\makeatletter
% Restore PDF resources that PGF reserved in the process that dumped the format.
\@ifundefined{pgf@sys@pdf@extgs@objnum}{}{%
  \def\MarkTwoTeXReserveObject#1{\pdfextension obj reserveobjnum%
    \edef#1{\the\numexpr\pdffeedback lastobj\relax}}%
  \MarkTwoTeXReserveObject\pgf@sys@pdf@extgs@objnum
  \MarkTwoTeXReserveObject\pgf@sys@pdf@pattern@objnum
  \MarkTwoTeXReserveObject\pgf@sys@pdf@colrospaces@objnum
  \pgf@sys@pdf@install@pageresources
}
\makeatother
"""
HIDE_DOZENT = r"""\NewCommandCopy{\MarkTwoTeXBeamerFootnote}{\footnote}
\RenewDocumentEnvironment{MarkTwoTeXDozent}{}{%
  \begin{visibleenv}<0>%
  \RenewDocumentCommand{\footnote}{o +m}{%
    \IfNoValueTF{##1}{\MarkTwoTeXBeamerFootnote<0>{##2}}{\MarkTwoTeXBeamerFootnote<0>[##1]{##2}}}%
}{\end{visibleenv}}
"""
SLIDE_FOOTER = r"""\setbeamertemplate{footline}{%
  \leavevmode\hbox to \paperwidth{\hskip10mm\sffamily\scriptsize
    \MarkTwoTeXFooter\hfil\insertframenumber\hskip10mm}\vskip3mm}
"""


def nonnegative_seconds(value):
    try:
        seconds = float(value)
    except ValueError:
        seconds = -1
    if not math.isfinite(seconds) or seconds < 0:
        raise argparse.ArgumentTypeError("expected a finite nonnegative number of seconds")
    return seconds


def parser():
    try:
        release = version("mark2tex")
    except PackageNotFoundError:
        release = "development checkout"
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source", type=Path, help="input .md or .markdown file")
    cli.add_argument("-o", "--output", type=Path, help="output PDF (default: beside the input)")
    cli.add_argument("--format", choices=("text", "handout", "slides"), default="text")
    cli.add_argument("--title", help="document title as plain text")
    cli.add_argument("--author", default="", help="author as plain text (default: empty)")
    cli.add_argument("--date", default="", help="date as plain text (default: empty)")
    cli.add_argument("--paper", choices=("a4", "letter"), default="a4")
    cli.add_argument("--language", default="ngerman", help="Babel language (default: ngerman)")
    cli.add_argument("--font-size", choices=("10", "11", "12"), help="body size in points")
    cli.add_argument("--template", choices=("stix",), default="stix", help="use the neutral STIX layout")
    cli.add_argument("--toc", action="store_true", help="insert a table of contents")
    cli.add_argument("--numbered", action="store_true", help="number section headings")
    cli.add_argument("--writing-margin", action="store_true", help="reserve a 72 mm right margin")
    cli.add_argument("--no-footer", action="store_true", help="hide the footer and page numbers")
    cli.add_argument("--slide-level", type=int, choices=range(1, 7), help="slide heading level (default: 2)")
    cli.add_argument("--dozent", action="store_true", help="show instructor-only content on slides")
    cli.add_argument("--speaker-notes", action="store_true", help="show presenter notes on a second screen")
    cli.add_argument("--cache", action="store_true", help="reuse successful builds in .mark2tex-cache")
    cli.add_argument("--cache-format", action="store_true", help="cache the static preamble (implies --cache)")
    cli.add_argument("--watch", action="store_true", help="rebuild when the Markdown source changes")
    cli.add_argument("--watch-delay", type=nonnegative_seconds, default=0.5,
                     help="seconds of quiet before rebuilding (default: 0.5)")
    cli.add_argument("-v", "--verbose", action="store_true", help="stream build diagnostics")
    cli.add_argument("--log", action="store_true", help="print the complete LaTeX log")
    cli.add_argument("--log-file", type=Path, help="copy the LaTeX log to a .log file")
    cli.add_argument("--keep-build", action="store_true", help="retain build files (always retained on failure)")
    cli.add_argument("--version", action="version", version=f"mark2tex {release}")
    return cli


def latex_text(value):
    escapes = {
        "\\": r"\textbackslash{}", "{": r"\{", "}": r"\}", "$": r"\$", "&": r"\&",
        "#": r"\#", "%": r"\%", "_": r"\_", "~": r"\textasciitilde{}", "^": r"\textasciicircum{}",
    }
    return "".join(" " if char.isspace() else escapes.get(char, char) for char in value)


def render(template, values):
    return re.sub(r"@([A-Z]+)@", lambda match: values[match[1]], template)


def run(command, build, env, transcript, verbose):
    with (build / transcript).open("w", encoding="utf-8") as log:
        with subprocess.Popen(command, cwd=build, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                              errors="replace", start_new_session=(os.name == "posix")) as process:
            try:
                for line in process.stdout:
                    log.write(line)
                    if verbose:
                        print(line, end="", file=sys.stderr, flush=True)
                return process.wait()
            except BaseException:
                if process.poll() is None:
                    if os.name == "posix":
                        os.killpg(process.pid, signal.SIGTERM)
                    else:
                        process.terminate()
                raise


def prepare_format(build, static, env, directory, identity, args):
    bootstrap = FORMAT_BOOTSTRAP + static + "\n\\dump\n"
    key = hashlib.sha256(identity + bootstrap.encode()).hexdigest()
    entry = directory / "formats" / (key + ".zip")
    inputs = cache.restore(entry, build, (FORMAT_FILE,))
    if inputs is not None:
        return inputs
    started = time.time_ns()
    print("Preparing LuaLaTeX format…", file=sys.stderr)
    (build / "format-bootstrap.tex").write_text(bootstrap, encoding="utf-8")
    command = ["lualatex", "-ini", "-jobname=mark2tex-format", "-recorder", "-interaction=nonstopmode",
               "-halt-on-error", "-no-shell-escape", "format-bootstrap.tex"]
    if run(command, build, env, "format-build.log", args.verbose) or not (build / FORMAT_FILE).is_file():
        return None
    try:
        inputs = cache.recorded_inputs(build / "mark2tex-format.fls", started)
        cache.save(entry, build, (FORMAT_FILE,), inputs)
        return inputs
    except OSError as error:
        print(f"Could not update the format cache: {error}", file=sys.stderr)
    return None


def validate(args):
    if args.format == "slides":
        if args.paper != "a4" or args.writing_margin or args.numbered or args.toc:
            raise ValueError("--paper letter, --writing-margin, --numbered and --toc apply to text and handout")
    elif args.dozent or args.speaker_notes:
        raise ValueError("--dozent and --speaker-notes require --format slides")
    if args.slide_level is not None and args.format == "text":
        raise ValueError("--slide-level requires --format handout or slides")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", args.language):
        raise ValueError("--language must be one Babel language name")
    if args.source.suffix.lower() not in (".md", ".markdown"):
        raise ValueError("input must be a .md or .markdown file")
    executables = {}
    for command in ("latexmk", "lualatex", "texlua"):
        executable = shutil.which(command)
        if not executable:
            raise ValueError(f"{command} is not on PATH")
        # Preserve the invocation name, since the two LuaTeX entry points can share a binary.
        executables[command] = str(Path(executable).absolute())
    return executables


def paths(args):
    source = args.source.expanduser().absolute()
    suffix = "" if args.format == "text" else "-" + args.format
    if args.dozent:
        suffix += "-dozent"
    if args.speaker_notes:
        suffix += "-speaker-notes"
    output = (args.output.expanduser() if args.output else source.with_name(source.stem + suffix + ".pdf")).resolve()
    logfile = args.log_file.expanduser().resolve() if args.log_file else None
    for path, extension in ((output, ".pdf"), (logfile, ".log")):
        if path and (path.suffix.lower() != extension or path.is_dir() or not path.parent.is_dir()
                     or path == source.resolve()):
            raise ValueError(f"expected a separate {extension} file in an existing directory: {path}")
    return source, output, logfile


def environment(source):
    env = os.environ.copy()
    # Relative entries in inherited search paths refer to the caller's working directory.
    for key, prefix in (
        ("TEXINPUTS", [".", str(TEX), str(source.parent)]),
        ("LUAINPUTS", [str(TEX), str(source.parent)]),
    ):
        inherited = [os.path.join(os.getcwd(), entry) if entry and not os.path.isabs(entry) else entry
                     for entry in env.get(key, "").split(os.pathsep)]
        env[key] = os.pathsep.join([*prefix, *inherited, ""])
    env["PATH"] = os.pathsep.join(os.path.abspath(entry) for entry in os.get_exec_path())
    return env


def cache_identity(env, executables):
    relevant = {key: value for key, value in env.items()
                if key.startswith(("TEX", "LUA", "KPATHSEA", "FONTCONFIG"))
                or key in ("PATH", "HOME", "SOURCE_DATE_EPOCH", "FORCE_SOURCE_DATE")}
    identity = hashlib.sha256(json.dumps(relevant, sort_keys=True).encode())
    for name, executable in executables.items():
        tool = Path(executable)
        info = tool.stat()
        release = subprocess.check_output([executable, "--version"], env=env)
        identity.update(f"{name}={tool.resolve()}:{info.st_size}:{info.st_mtime_ns}".encode())
        identity.update(release)
    sources = [Path(__file__), HERE / "cache.py", TEX / "mark2tex.lua", TEX / "mark2tex.sty",
               TEX / "scripts/convert.lua", *sorted((TEX / "src/mark2tex").glob("*.lua")),
               *sorted(TEMPLATES.glob("*.tex"))]
    for path in sources:
        identity.update(path.name.encode())
        identity.update(path.read_bytes())
    return identity.digest()


def convert(build, source, content, args, executable, env):
    (build / "source.md").write_bytes(content)
    command = [executable, str(TEX / "scripts/convert.lua"), "source.md", "fragment",
               f"document_id={source}"]
    if args.format != "text":
        command.extend([f"profile={args.format}", f"slide_level={args.slide_level or 2}"])
    if args.dozent:
        command.append("slide_audience=dozent")
    result = subprocess.run(command, cwd=build, env=env, capture_output=True,
                            text=True, encoding="utf-8", errors="replace")
    (build / "convert.log").write_text(result.stderr, encoding="utf-8")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    fragment = result.stdout.strip()
    if result.returncode or not fragment or not (build / fragment).is_file():
        raise ValueError(f"Markdown conversion failed; see {build / 'convert.log'}")
    return fragment


def stage_document(build, args, fragment):
    slides = args.format == "slides"
    body = (rf"\fontsize{{{args.font_size}pt}}{{{int(args.font_size) * 1.5:g}pt}}\selectfont"
            if args.font_size else r"\fontsize{12.75bp}{19.125bp}\selectfont")
    common = render((TEMPLATES / "common.tex").read_text(encoding="utf-8"), {"BODY": body})
    (build / "common.tex").write_text(common, encoding="utf-8")
    footer = SLIDE_FOOTER if slides else ""
    if args.no_footer:
        footer = r"\setbeamertemplate{footline}{}" if slides else r"\pagestyle{empty}"
    titlepage = r"\begin{frame}\titlepage\end{frame}" if slides else r"\maketitle"
    values = {
        "PAPER": args.paper, "SIZE": args.font_size or "11", "LANGUAGE": args.language,
        "MARGINS": ("left=18mm,right=72mm,top=20mm,bottom=20mm" if args.writing_margin
                    else "textwidth=155mm,top=27mm,bottom=25mm"),
        "NUMBERING": "3" if args.numbered else "0", "TOC": r"\tableofcontents\clearpage" if args.toc else "",
        "TITLE": latex_text(args.title or ""), "AUTHOR": latex_text(args.author), "DATE": latex_text(args.date),
        "TITLEPAGE": titlepage if args.title is not None else "", "FRAGMENT": fragment, "FOOTER": footer,
        "NOTES": r"\setbeameroption{show notes on second screen=right}" if args.speaker_notes else "",
        "DOZENT": "" if args.dozent else HIDE_DOZENT,
    }
    template = TEMPLATES / ("slides.tex" if slides else "article.tex")
    return render(template.read_text(encoding="utf-8"), values)


def diagnostics(build, args, logfile, failed):
    log = build / "document.log"
    if not log.is_file():
        log = build / "build.log"
    if not log.is_file():
        log = build / "convert.log"
    if logfile and log.is_file():
        cache.publish(log, logfile)
    if log.is_file() and (args.log or (failed and not args.verbose)):
        content = log.read_text(encoding="utf-8", errors="replace")
        print(content if args.log else "\n".join(content.splitlines()[-40:]), file=sys.stderr)
    return log


def compile_pdf(args, executables, current=lambda: True):
    source, output, logfile = paths(args)
    content = source.read_bytes()
    env = environment(source)
    env["TEXMFCACHE"] = os.path.abspath(env["TEXMFCACHE"]) if env.get("TEXMFCACHE") else "tex-cache"
    directory = Path.cwd() / ".mark2tex-cache"
    use_cache = (args.cache or args.cache_format) and not args.keep_build and not args.verbose
    identity = cache_identity(env, executables) if args.cache or args.cache_format else b""
    # Operational flags and output destinations do not change the rendered PDF.
    render_options = ("format", "title", "author", "date", "paper", "language", "font_size",
                      "toc", "numbered", "writing_margin", "no_footer", "slide_level", "dozent", "speaker_notes")
    options = json.dumps([str(source), *(getattr(args, option) for option in render_options)])
    key = hashlib.sha256(identity + options.encode() + b"\0" + content).hexdigest()
    entry = directory / "builds" / (key + ".zip")
    try_format = args.cache_format
    allow_cache_hit = use_cache

    while True:
        build = Path(tempfile.mkdtemp(prefix="mark2tex-"))
        success = False
        retry = False
        try:
            if not allow_cache_hit or cache.restore(entry, build, BUILD_FILES) is None:
                (build / "tex-cache").mkdir()
                try:
                    fragment = convert(build, source, content, args, executables["texlua"], env)
                except ValueError:
                    diagnostics(build, args, logfile, failed=True)
                    raise
                document = stage_document(build, args, fragment)
                static, dynamic = document.split(RUNTIME_BOUNDARY, 1)
                format_inputs = prepare_format(build, static, env, directory, identity, args) if try_format else None
                if try_format and format_inputs is None:
                    retry = True
                    continue
                command = [executables["latexmk"], "-norc", "-lualatex", "-bibtex-", "-recorder",
                           "-interaction=nonstopmode", "-halt-on-error", "-file-line-error", "-no-shell-escape"]
                if format_inputs is not None:
                    document = FORMAT_RUNTIME + dynamic
                    command.append(f"-fmt=./{FORMAT_FILE}")
                (build / "document.tex").write_text(document, encoding="utf-8")
                print(f"Compiling {source.name}…", file=sys.stderr)
                started = time.time_ns()
                failed = run([*command, "document.tex"], build, env, "build.log", args.verbose)
                if failed or not (build / "document.pdf").is_file():
                    if format_inputs is not None:
                        retry = True
                        continue
                    log = diagnostics(build, args, logfile, failed=True)
                    raise ValueError(f"LaTeX compilation failed; see {log}")
                if args.cache or args.cache_format:
                    try:
                        inputs = cache.recorded_inputs(build / "document.fls", started)
                        inputs.update(format_inputs or {})
                        cache.save(entry, build, BUILD_FILES, inputs)
                    except OSError as error:
                        print(f"Could not update the build cache: {error}", file=sys.stderr)
            else:
                print(f"Reusing cached build for {source.name}.", file=sys.stderr)
            if current():
                diagnostics(build, args, logfile, failed=False)
            if cache.publish(build / "document.pdf", output, current):
                print(output, flush=True)
            else:
                print(f"Skipped outdated PDF for {source.name}.", file=sys.stderr)
            success = True
            return
        finally:
            if retry:
                try_format = False
                allow_cache_hit = False
                print("Retrying with a fresh regular build.", file=sys.stderr)
            if args.keep_build or not success:
                print(f"Build files: {build}", file=sys.stderr)
            else:
                shutil.rmtree(build)


def signature(source):
    try:
        info = source.stat()
    except FileNotFoundError:
        return None
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def watch(args, executables):
    source, _, _ = paths(args)
    previous = signature(source)
    print(f"Watching {source} (delay: {args.watch_delay:g}s).", file=sys.stderr)
    while True:
        try:
            compile_pdf(args, executables, lambda: signature(source) == previous)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            print(f"mark2tex: {error}", file=sys.stderr)
        while signature(source) == previous:
            time.sleep(0.05)
        previous = signature(source)
        changed = time.monotonic()
        while time.monotonic() - changed < args.watch_delay:
            time.sleep(min(0.05, args.watch_delay))
            current = signature(source)
            if current != previous:
                previous, changed = current, time.monotonic()


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        executables = validate(args)
        if args.watch:
            watch(args, executables)
        else:
            compile_pdf(args, executables)
    except KeyboardInterrupt:
        return 130 if not args.watch else 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"mark2tex: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
