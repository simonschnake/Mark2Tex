"""Exercise an installed Mark2TeX wheel outside the source checkout.

Run with the wheel's Python interpreter and pass its mark2tex executable.
Requires TeX Live and Poppler (pdftotext and pdfimages).
"""

from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
import zlib

from mark2tex_cli.cli import HERE, TEMPLATES, TEX


DOCUMENT = r"""# Measurement

## Calibration

Public measurement. See [reference](https://example.org).[^instrument]

\includegraphics[width=8mm]{images/sample.png}

. . .

Updated reading.

<!-- script: begin -->

ScriptVariant

<!-- instructor: begin -->

InstructorScriptVariant

<!-- end -->

<!-- end -->

<!-- slides: begin -->

SlidesVariant

<!-- end -->

<!-- student: begin -->

StudentVariant

<!-- end -->

<!-- dozent:begin -->

InstructorOnly

<!-- dozent:end -->

<!-- note: PresenterOnly -->

---

<!-- title: Continuation -->

Response to the calibration.

[^instrument]: Instrument reference.

\begin{Lernblock}{Worked Example}
Manual example.
\end{Lernblock}
"""


def png(path, color):
    def chunk(name, data):
        return (struct.pack(">I", len(data)) + name + data
                + struct.pack(">I", zlib.crc32(name + data)))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress((b"\0" + color * 2) * 2))
                     + chunk(b"IEND", b""))


def pdf_text(pdf):
    return subprocess.check_output(["pdftotext", str(pdf), "-"], text=True)


def integration(binary, work):
    source = work / "source files" / "measurement.md"
    image = source.parent / "images/sample.png"
    image.parent.mkdir(parents=True)
    source.write_text(DOCUMENT)
    png(image, b"\xff\x00\x00")

    def build(*options, status=0):
        result = subprocess.run([binary, str(source), "--language", "english", *options],
                                cwd=work, capture_output=True, text=True, timeout=180)
        assert result.returncode == status, (result.stdout, result.stderr)
        return result

    for suffix, options in (
        ("", []),
        ("-handout", ["--format", "handout", "--paper", "letter", "--writing-margin", "--toc"]),
        ("-handout-dozent", ["--format", "handout", "--instructor"]),
        ("-slides", ["--format", "slides", "--h1", "hide"]),
        ("-slides-dozent", ["--format", "slides", "--dozent"]),
        ("-slides-speaker-notes", ["--format", "slides", "--speaker-notes"]),
    ):
        cold = build("--title", "Calibration & results", "--cache-format", *options)
        assert "Retrying" not in cold.stderr, cold.stderr
        pdf = source.with_name("measurement" + suffix + ".pdf")
        text = pdf_text(pdf)
        assert "Calibration & results" in text and "Worked Example" in text, text
        assert "Instrument reference" in text, text
        slides = suffix.startswith("-slides")
        instructor = suffix.endswith("-dozent")
        assert ("ScriptVariant" in text.replace("InstructorScriptVariant", "")) == (not slides), text
        assert ("InstructorScriptVariant" in text) == (instructor and not slides), text
        assert ("SlidesVariant" in text) == slides, text
        assert ("StudentVariant" in text) == (not instructor), text
        if suffix == "-slides":
            assert "Measurement" not in text, text
        if slides:
            assert "Continuation" in text, text
            assert ("InstructorOnly" in text) == suffix.endswith("-dozent"), text
            assert ("PresenterOnly" in text) == suffix.endswith("-speaker-notes"), text
        images = subprocess.check_output(["pdfimages", "-list", str(pdf)], text=True)
        assert len(images.splitlines()) > 2, images

    output = work / "output.pdf"
    log = work / "build.log"
    options = ["--cache-format", "--log-file", str(log), "-o", str(output)]
    assert "Compiling" in build(*options).stderr
    assert "Reusing cached build" in build(*options).stderr
    png(image, b"\x00\xff\x00")
    assert "Compiling" in build(*options).stderr
    assert "Reusing cached build" in build(*options).stderr

    # A valid ZIP containing a damaged format must trigger a regular build.
    article_formats = []
    for entry in (work / ".mark2tex-cache/formats").glob("*.zip"):
        with zipfile.ZipFile(entry) as archive:
            inputs = archive.read("inputs.json")
            if b"beamer.cls" not in inputs and b"size11.clo" in inputs:
                article_formats.append((entry, inputs))
    assert article_formats
    for entry, inputs in article_formats:
        with zipfile.ZipFile(entry, "w") as archive:
            archive.writestr("inputs.json", inputs)
            archive.writestr("mark2tex-format.fmt", b"broken format")
    source.write_text(DOCUMENT.replace("Public measurement", "Revised measurement"))
    assert "Retrying with a fresh regular build" in build(*options).stderr
    assert "Revised measurement" in pdf_text(output)
    successful_pdf = output.read_bytes()

    source.write_text(DOCUMENT + "\n\\UnknownCalibrationCommand\n")
    failure = build(*options, status=1)
    assert "Build files:" in failure.stderr and "UnknownCalibrationCommand" in log.read_text()
    assert output.read_bytes() == successful_pdf

    # Changing either bundled asset must invalidate a build for unchanged source.
    source.write_text(DOCUMENT)
    for asset in (TEMPLATES / "common.tex", TEX / "src/mark2tex/core.lua"):
        original = asset.read_bytes()
        try:
            asset.write_bytes(original + b"\n")
            assert "Compiling" in build(*options).stderr
        finally:
            asset.write_bytes(original)

    # A complete external wrapper controls layout and receives CLI variant data.
    template = work / "custom layout" / "layout.tex"
    template.parent.mkdir()
    template.with_name("header.tex").write_text(r"\newcommand{\CustomHeader}{Custom layout}")
    template.write_text(r"""
\documentclass[aspectratio=169]{beamer}
\input{mark2tex-template.tex}
\input{header.tex}
\usepackage{mark2tex}
\MarkTwoTeXHideDozent
\ifMarkTwoTeXSpeakerNotes
  \setbeameroption{show notes on second screen=right}
\fi
\NewDocumentEnvironment{Lernblock}{s m +b}{\begin{frame}{#2}#3\end{frame}}{}
\begin{document}
\begin{frame}{\CustomHeader}
  \MarkTwoTeXTitle\par
  \ifMarkTwoTeXHasTitleImage
    \includegraphics[width=8mm]{\MarkTwoTeXTitleImage}
  \fi
\end{frame}
\MarkTwoTeXContent
\end{document}
""")
    cover = work / "cover picture.png"
    png(cover, b"\x00\x00\xff")
    custom_pdf = work / "custom.pdf"
    custom_options = [
        "--format", "slides", "--template", str(template), "--title", "Built & supplied",
        "--title-image", str(cover), "--cache-format", "-o", str(custom_pdf),
    ]
    source.write_text(DOCUMENT)
    regular = build(*custom_options)
    assert "Preparing LuaLaTeX format" not in regular.stderr
    text = pdf_text(custom_pdf)
    assert "Custom layout" in text and "InstructorOnly" not in text, text
    warm = build(*custom_options)
    assert "Reusing cached build" in warm.stderr, (regular.stderr, warm.stderr)
    png(cover, b"\xff\x00\xff")
    assert "Compiling" in build(*custom_options).stderr
    build(*custom_options, "--dozent", "--speaker-notes")
    text = pdf_text(custom_pdf)
    assert "InstructorOnly" in text and "PresenterOnly" in text, text

    # Watch must recover from failure and discard a build overtaken by an edit.
    watcher_pdf = work / "watch.pdf"
    source.write_text(DOCUMENT + "\n\\UnknownCalibrationCommand\n")
    with (work / "watch.log").open("w+") as watch_log:
        watcher = subprocess.Popen(
            [binary, str(source), "--watch", "--watch-delay", "0.25", "-o", str(watcher_pdf)],
            cwd=work, stdout=watch_log, stderr=watch_log,
        )
        try:
            def wait_for(condition):
                deadline = time.monotonic() + 120
                while time.monotonic() < deadline:
                    if condition():
                        return
                    assert watcher.poll() is None
                    time.sleep(0.02)
                raise AssertionError((work / "watch.log").read_text())

            transcript = work / "watch.log"
            wait_for(lambda: "LaTeX compilation failed" in transcript.read_text())
            source.write_text(DOCUMENT.replace("Public measurement", "Intermediate measurement"))
            wait_for(lambda: transcript.read_text().count("Compiling") >= 2)
            source.write_text(DOCUMENT.replace("Public measurement", "Final measurement"))
            wait_for(watcher_pdf.exists)
            assert "Final measurement" in pdf_text(watcher_pdf)
            assert "Skipped outdated PDF" in transcript.read_text()
        finally:
            watcher.send_signal(signal.SIGINT)
            watcher.wait(timeout=20)


if __name__ == "__main__":
    assert (HERE / "tex").is_dir(), "run from an installed wheel"
    with tempfile.TemporaryDirectory(prefix="mark2tex-integration-") as directory:
        integration(str(Path(sys.argv[1]).absolute()), Path(directory))
    print("Installed CLI checks passed")
