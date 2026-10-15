import os
import threading

import pytest

from frontend import elm


@pytest.fixture
def elm_project(tmp_path, monkeypatch):
    (tmp_path / "src").mkdir()
    (tmp_path / "elm.json").write_text("{}")
    (tmp_path / "src" / "Main.elm").write_text("module Main exposing (main)")
    monkeypatch.setattr(elm, "ELM_DIR", tmp_path)
    monkeypatch.setattr(elm, "OUTPUT_DIR", tmp_path)
    monkeypatch.setattr(elm, "PROGRAMS", {"src/Main.elm": "main.js"})
    return tmp_path


def set_mtime(path, seconds):
    os.utime(path, ns=(seconds * 10**9, seconds * 10**9))


def test_bundle_is_stale_when_it_has_not_been_built(elm_project):
    assert elm.bundle_is_stale()


def test_bundle_is_fresh_when_built_after_every_source(elm_project):
    set_mtime(elm_project / "elm.json", 100)
    set_mtime(elm_project / "src" / "Main.elm", 100)
    bundle, = elm.outputs()
    bundle.write_text("compiled")
    set_mtime(bundle, 200)

    assert not elm.bundle_is_stale()


def test_bundle_is_stale_when_a_source_changed_after_the_build(elm_project):
    bundle, = elm.outputs()
    bundle.write_text("compiled")
    set_mtime(bundle, 200)
    set_mtime(elm_project / "elm.json", 100)
    set_mtime(elm_project / "src" / "Main.elm", 300)

    assert elm.bundle_is_stale()


def test_bundle_is_stale_when_one_program_has_not_been_built(elm_project, monkeypatch):
    monkeypatch.setattr(elm, "PROGRAMS", {"src/Main.elm": "main.js", "src/Other.elm": "other.js"})
    set_mtime(elm_project / "elm.json", 100)
    set_mtime(elm_project / "src" / "Main.elm", 100)
    (elm_project / "main.js").write_text("compiled")
    set_mtime(elm_project / "main.js", 200)

    assert elm.bundle_is_stale()


def test_source_mtimes_includes_nested_modules(elm_project):
    (elm_project / "src" / "Page").mkdir()
    (elm_project / "src" / "Page" / "Editor.elm").write_text("module Page.Editor exposing (..)")

    assert elm_project / "src" / "Page" / "Editor.elm" in elm.source_mtimes()


def test_watch_calls_back_when_a_source_changes(elm_project):
    changed = threading.Event()
    elm.watch(changed.set, interval=0.05)

    set_mtime(elm_project / "src" / "Main.elm", 500)

    assert changed.wait(timeout=2)


def test_compile_elm_raises_when_the_compiler_is_missing(elm_project, monkeypatch):
    monkeypatch.setattr(elm.shutil, "which", lambda _: None)

    with pytest.raises(elm.ElmNotInstalled):
        elm.compile_elm()
