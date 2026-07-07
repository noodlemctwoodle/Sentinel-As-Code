#!/usr/bin/env python3
"""Populate a Word .docx table-of-contents field (entries + page numbers)
in place, headlessly, using LibreOffice through the UNO API.

Pandoc emits a genuine Word TOC field but cannot paginate, so the field is
empty until a layout engine fills it in. Running a Basic macro from the
soffice command line is documented as unreliable in headless mode (it often
"runs but does nothing"), so this uses the UNO socket/pipe approach instead:
start a private LibreOffice listener, connect, open the document, force each
content index to build from the heading outline, update it, and save.

Requires the `uno` module. On the Ubuntu CI agent:
    apt-get install -y libreoffice-writer python3-uno

Usage:
    python3 Update-WordToc.py <path-to-docx> [soffice-executable]

Exit codes: 0 success, 2 bad args, 3 uno module missing, 4 no connection.
"""
import os
import shutil
import sys
import tempfile
import time
import uuid

try:
    import uno
    from com.sun.star.beans import PropertyValue
    from com.sun.star.connection import NoConnectException
except ImportError:
    sys.stderr.write("python3 'uno' module not found (install python3-uno)\n")
    sys.exit(3)


def _prop(name, value):
    p = PropertyValue()
    p.Name = name
    p.Value = value
    return p


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: Update-WordToc.py <docx> [soffice]\n")
        return 2
    docx = os.path.abspath(sys.argv[1])
    soffice = sys.argv[2] if len(sys.argv) > 2 else "soffice"
    if not os.path.isfile(docx):
        sys.stderr.write("file not found: %s\n" % docx)
        return 2

    profile = tempfile.mkdtemp(prefix="lo-toc-")
    pipe = "unotoc_" + uuid.uuid4().hex
    conn = "pipe,name=%s;urp;StarOffice.ComponentContext" % pipe

    import subprocess
    try:
        proc = subprocess.Popen([
            soffice, "--headless", "--invisible", "--norestore", "--nologo",
            "--nodefault", "--nofirststartwizard",
            "--accept=" + conn.replace(";StarOffice.ComponentContext", ""),
            "-env:UserInstallation=" + uno.systemPathToFileUrl(profile),
        ])
    except (FileNotFoundError, OSError) as exc:
        shutil.rmtree(profile, ignore_errors=True)
        sys.stderr.write("could not start soffice (%s): %s\n" % (soffice, exc))
        return 4

    try:
        local = uno.getComponentContext()
        resolver = local.ServiceManager.createInstanceWithContext(
            "com.sun.star.bridge.UnoUrlResolver", local)
        ctx = None
        # First run of a fresh profile initialises before it listens, so
        # poll for the connection rather than assuming it is immediately up.
        for _ in range(120):
            if proc.poll() is not None:
                sys.stderr.write("soffice exited before it was ready\n")
                return 4
            try:
                ctx = resolver.resolve("uno:" + conn)
                break
            except NoConnectException:
                time.sleep(0.5)
        if ctx is None:
            sys.stderr.write("could not connect to LibreOffice\n")
            return 4

        smgr = ctx.ServiceManager
        desktop = smgr.createInstanceWithContext(
            "com.sun.star.frame.Desktop", ctx)
        doc = desktop.loadComponentFromURL(
            uno.systemPathToFileUrl(docx), "_blank", 0, (_prop("Hidden", True),))
        try:
            indexes = doc.getDocumentIndexes()
            updated = 0
            for i in range(indexes.getCount()):
                idx = indexes.getByIndex(i)
                # Pandoc's TOC field imports with outline-building off, so a
                # plain update() yields an empty TOC. Force it on.
                if idx.supportsService("com.sun.star.text.ContentIndex"):
                    idx.CreateFromOutline = True
                idx.update()
                updated += 1
            doc.store()
            sys.stderr.write("updated %d index(es)\n" % updated)
        finally:
            doc.close(False)
            try:
                desktop.terminate()
            except Exception:
                pass
        return 0
    finally:
        try:
            proc.wait(timeout=30)
        except Exception:
            proc.terminate()
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
