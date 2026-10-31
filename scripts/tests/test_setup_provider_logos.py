"""scripts/setup_provider_logos.py の単体テスト。ネットワークには出ない。

実行: python3 -m unittest discover -s scripts/tests
"""

from __future__ import annotations

import contextlib
import hashlib
import http.client
import importlib.util
import io
import json
import os
import re
import stat
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
BUNDLED_LOGOS = {
    "claude.svg",
    "openai.svg",
    "antigravity.svg",
    "grok.svg",
    "pixellab.svg",
}


def _load_script():
    path = ROOT / "scripts" / "setup_provider_logos.py"
    spec = importlib.util.spec_from_file_location("setup_provider_logos", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


logos = _load_script()
SetupError = logos.SetupError

# 区切りの省略・円弧フラグの連結・指数表記を含む自作のパスデータ。
# ブランドのロゴではない。
TRICKY_D = (
    "M1.5 2.25v-1.2c0-.19.072-.333.238-.428l4.5-2.6a.797.797 0 00-.856 0z"
    "M3 3h2v2H3z m1e-1,2E+0L-.5-.5"
)
# lobehub の SVG と同じ属性の並び (currentColor・evenodd・1em・style・title)。
LOBEHUB_SHAPED = (
    '<svg fill="currentColor" fill-rule="evenodd" height="1em"'
    ' style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em"'
    ' xmlns="http://www.w3.org/2000/svg"><title>Example</title>'
    f'<path d="{TRICKY_D}"></path></svg>'
).encode()


def _svg(body: str, root: str = 'viewBox="0 0 24 24"') -> bytes:
    return f'<svg xmlns="http://www.w3.org/2000/svg" {root}>{body}</svg>'.encode()


def _path(d: str = "M0 0h1v1H0z", extra: str = "") -> str:
    return f'<path d="{d}"{extra}/>'


class NormalizeSvgTests(unittest.TestCase):
    """正規化した SVG の形。"""

    def test_lobehub_shape_becomes_contract_shape(self) -> None:
        """Lobehub と同じ形の SVG を、決めた形へ書き直す。"""
        expected = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"'
            ' width="24" height="24">'
            f'<path d="{TRICKY_D}" fill="#000000" fill-rule="evenodd"/></svg>\n'
        ).encode()
        self.assertEqual(logos.normalize_svg(LOBEHUB_SHAPED, "test"), expected)

    def test_path_data_is_kept_verbatim(self) -> None:
        """パスデータを一字も変えず、文書の順に残す。"""
        second = "M0,0 L10,0 10,10 Z"
        output = logos.normalize_svg(_svg(_path(TRICKY_D) + _path(second)), "test")
        self.assertEqual(
            re.findall(r' d="([^"]*)"', output.decode()), [TRICKY_D, second]
        )

    def test_width_and_height_follow_view_box(self) -> None:
        """幅と高さを viewBox からとる (縦横が違う場合も)。"""
        cases = {
            'viewBox="0 0 24 19.2" width="1em" height="1em"': (
                "0 0 24 19.2",
                "24",
                "19.2",
            ),
            'viewBox="0,0,24,19.2"': ("0 0 24 19.2", "24", "19.2"),
            'viewBox=" -2 -1.5  30 12.25 "': ("-2 -1.5 30 12.25", "30", "12.25"),
        }
        for root, (view_box, width, height) in cases.items():
            with self.subTest(root=root):
                output = logos.normalize_svg(_svg(_path(), root), "test").decode()
                expected = f'viewBox="{view_box}" width="{width}" height="{height}">'
                self.assertIn(expected, output)

    def test_fill_rule_follows_inheritance(self) -> None:
        """塗りの規則は path の指定を優先し、無ければルートの指定を引き継ぐ。"""
        cases = [
            ('fill-rule="evenodd"', "", True),
            ("", ' fill-rule="evenodd"', True),
            ('fill-rule="evenodd"', ' fill-rule="nonzero"', False),
            ('fill-rule="nonzero"', "", False),
            ("", "", False),
        ]
        for root_rule, path_rule, evenodd in cases:
            with self.subTest(root=root_rule, path=path_rule):
                root = f'viewBox="0 0 24 24" {root_rule}'
                output = logos.normalize_svg(_svg(_path(extra=path_rule), root), "test")
                self.assertEqual(b'fill-rule="evenodd"' in output, evenodd)
                self.assertNotIn(b"nonzero", output)

    def test_solid_fill_is_replaced_with_black(self) -> None:
        """単色の塗りは #000000 にそろえる。"""
        for fill in ("currentColor", "#5d5e5e", "#fff"):
            with self.subTest(fill=fill):
                root = f'viewBox="0 0 24 24" fill="{fill}"'
                data = _svg(_path(extra=f' fill="{fill}"'), root)
                output = logos.normalize_svg(data, "test")
                self.assertIn(b'fill="#000000"', output)
                self.assertNotIn(fill.encode(), output)

    def test_drops_declaration_comments_and_title(self) -> None:
        """XML 宣言・コメント・title を受け付け、出力からは落とす。"""
        data = (
            b'<?xml version="1.0" encoding="UTF-8"?>\n<!-- comment -->\n'
            b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">\n'
            b'  <title>Example</title>\n  <path d="M0 0h1v1H0z"/>\n</svg>\n'
        )
        expected = (
            b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"'
            b' width="24" height="24"><path d="M0 0h1v1H0z" fill="#000000"/></svg>\n'
        )
        self.assertEqual(logos.normalize_svg(data, "test"), expected)

    def test_normalized_output_is_stable(self) -> None:
        """正規化した結果をもう一度通しても変わらない。"""
        once = logos.normalize_svg(LOBEHUB_SHAPED, "test")
        self.assertEqual(logos.normalize_svg(once, "test"), once)


class RejectionTests(unittest.TestCase):
    """受け付けない SVG はエラーにする。"""

    def assert_rejected(self, data: bytes, fragment: str) -> None:
        """SetupError になり、文面に取得元と fragment が入ることを確かめる。"""
        with self.assertRaises(SetupError) as context:
            logos.normalize_svg(data, "sample.svg")
        self.assertIn("sample.svg", str(context.exception))
        self.assertIn(fragment, str(context.exception))

    def test_rejects_disallowed_elements(self) -> None:
        """許可していない要素 (svg・title・path 以外) を拒否する。"""
        elements = (
            "g",
            "use",
            "image",
            "script",
            "style",
            "defs",
            "foreignObject",
            "linearGradient",
            "radialGradient",
            "mask",
            "clipPath",
            "symbol",
            "pattern",
            "filter",
            "text",
            "a",
            "desc",
            "metadata",
            "switch",
        )
        for element in elements:
            with self.subTest(element=element):
                self.assert_rejected(_svg(f"<{element}/>" + _path()), f"<{element}>")

    def test_rejects_misplaced_elements(self) -> None:
        """要素の入れ子と置き場所を確かめる。"""
        cases = {
            "path in path": (_svg(f"<path d='M0 0'>{_path()}</path>"), "<path> の中"),
            "title in path": (_svg("<path d='M0 0'><title>x</title></path>"), "<path>"),
            "path in title": (_svg(f"<title>{_path()}</title>{_path()}"), "<title>"),
            "svg in svg": (_svg('<svg viewBox="0 0 1 1"/>' + _path()), "<svg> の中"),
            "path as root": (
                b'<path xmlns="http://www.w3.org/2000/svg" d="M0 0"/>',
                "ルート",
            ),
        }
        for label, (data, fragment) in cases.items():
            with self.subTest(case=label):
                self.assert_rejected(data, fragment)

    def test_rejects_disallowed_attributes(self) -> None:
        """要素ごとに決めた属性の外は拒否する。"""
        root = 'viewBox="0 0 24 24"'
        cases = [
            (_svg(_path(extra=' transform="rotate(90)"')), "transform"),
            (_svg(_path(extra=' style="fill:red"')), "style"),
            (_svg(_path(extra=' class="cls-1"')), "class"),
            (_svg(_path(extra=' id="a"')), "id"),
            (_svg(_path(extra=' stroke="#000"')), "stroke"),
            (_svg(_path(extra=' opacity="0.5"')), "opacity"),
            (_svg(_path(extra=' clip-path="url(#c)"')), "clip-path"),
            (_svg(_path(extra=' href="https://example.com/a.svg"')), "href"),
            (_svg(_path(), f'{root} transform="scale(2)"'), "transform"),
            (_svg(_path(), f'{root} id="layer_1"'), "id"),
            (_svg(_path(), f'{root} data-name="layer 1"'), "data-name"),
            (_svg(_path(), f'{root} version="1.1"'), "version"),
            (_svg('<title lang="en">x</title>' + _path()), "lang"),
        ]
        for data, attribute in cases:
            with self.subTest(attribute=attribute, data=data):
                self.assert_rejected(data, f"属性 {attribute}")

    def test_rejects_namespaced_href(self) -> None:
        """名前空間付きの外部参照 (xlink:href) を拒否する。"""
        data = (
            b'<svg xmlns="http://www.w3.org/2000/svg"'
            b' xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24">'
            b'<path d="M0 0" xlink:href="https://example.com/a.svg"/></svg>'
        )
        self.assert_rejected(data, "href (名前空間 http://www.w3.org/1999/xlink)")

    def test_rejects_style_that_affects_rendering(self) -> None:
        """描画に効く style のプロパティを拒否する。"""
        styles = (
            "transform:rotate(90deg)",
            "fill:url(#g)",
            "display:none",
            "flex:none;opacity:0.5",
            "flex",
        )
        for style in styles:
            with self.subTest(style=style):
                root = f'viewBox="0 0 24 24" style="{style}"'
                self.assert_rejected(_svg(_path(), root), "style")

    def test_rejects_non_solid_paint(self) -> None:
        """単色でない塗りと、知らない塗りの規則を拒否する。"""
        for fill in ("url(#gradient)", "none", "red", "rgb(0,0,0)", "#12345"):
            with self.subTest(fill=fill):
                data = _svg(_path(extra=f' fill="{fill}"'))
                self.assert_rejected(data, f'fill="{fill}"')
        data = _svg(_path(extra=' fill-rule="inherit"'))
        self.assert_rejected(data, 'fill-rule="inherit"')

    def test_rejects_invalid_view_box(self) -> None:
        """不正な viewBox を拒否する。"""
        self.assert_rejected(_svg(_path(), 'width="24" height="24"'), "viewBox が無い")
        for view_box in ("0 0 24", "0 0 24 24 1", "0 0 0 24", "0 0 24 -1", "a b c d"):
            with self.subTest(view_box=view_box):
                self.assert_rejected(_svg(_path(), f'viewBox="{view_box}"'), "viewBox")
        self.assert_rejected(_svg(_path(), 'viewBox="0 0 2.4e1 24"'), "viewBox")
        self.assert_rejected(_svg(_path(), 'viewBox=""'), "viewBox")

    def test_rejects_invalid_path_data(self) -> None:
        """パスデータとして読めない d を拒否する。"""
        self.assert_rejected(_svg("<path/>"), "d の無い path")
        for d in ("", "0 0 1 1", "M0 0 url(#x)", "M0 0 &lt;script&gt;"):
            with self.subTest(d=d):
                self.assert_rejected(_svg(_path(d)), "パスデータとして読めない")

    def test_rejects_svg_without_path(self) -> None:
        """Path が 1 つも無い SVG を拒否する。"""
        self.assert_rejected(_svg("<title>x</title>"), "path が 1 つも無い")

    def test_rejects_doctype(self) -> None:
        """DOCTYPE (エンティティの定義) を拒否する。"""
        data = (
            b'<!DOCTYPE svg [<!ENTITY x "M0 0h1v1H0z">]>'
            b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            b'<path d="&x;"/></svg>'
        )
        self.assert_rejected(data, "DOCTYPE")

    def test_rejects_processing_instructions(self) -> None:
        """処理命令 (外部 CSS の読み込みなど) を拒否する。"""
        stylesheet = b'<?xml-stylesheet href="https://example.com/a.css"?>'
        self.assert_rejected(stylesheet + _svg(_path()), "xml-stylesheet")

    def test_rejects_elements_outside_svg_namespace(self) -> None:
        """SVG の名前空間に無い要素を拒否する。"""
        no_namespace = b'<svg viewBox="0 0 24 24"><path d="M0 0"/></svg>'
        self.assert_rejected(no_namespace, "名前空間")
        foreign = _svg('<x:path xmlns:x="https://example.com/ns" d="M0 0"/>')
        self.assert_rejected(foreign, "名前空間")

    def test_rejects_stray_text(self) -> None:
        """Title の外にある文字列を拒否する。"""
        self.assert_rejected(_svg("text" + _path()), "文字列")
        self.assert_rejected(_svg("<path d='M0 0'>text</path>"), "文字列")

    def test_rejects_malformed_xml(self) -> None:
        """XML として読めない入力を拒否する。"""
        self.assert_rejected(_svg("<path d='M0 0'>"), "XML として読めない")
        self.assert_rejected(b"", "XML として読めない")


class CommittedFilesTests(unittest.TestCase):
    """リポジトリに置いた lock・自作のロゴ・ライセンス。"""

    def setUp(self) -> None:
        """リポジトリの lock を読む。"""
        text = (ROOT / logos.LOCK_PATH).read_text(encoding="utf-8")
        self.lock = json.loads(text)

    def test_lock_shape(self) -> None:
        """リポジトリの lock の形を確かめる。"""
        self.assertEqual(list(self.lock), list(logos.LOCK_KEYS))
        package, version = self.lock["package"], self.lock["version"]
        self.assertEqual(package, "@lobehub/icons-static-svg")
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        base_url = f"https://unpkg.com/{package}@{version}/icons/"
        self.assertEqual(self.lock["base_url"], base_url)
        self.assertEqual(self.lock["license"], "Resources/LICENSE-lobe-icons.txt")
        remote = {"openai.svg", "claude.svg", "antigravity.svg", "grok.svg"}
        self.assertEqual(set(self.lock["files"]), remote)
        for name, digest in self.lock["files"].items():
            with self.subTest(name=name):
                self.assertRegex(digest, r"^[0-9a-f]{64}$")
        self.assertEqual(self.lock["local"], ["pixellab.svg"])
        logos.validate_lock(self.lock, ROOT)

    def test_outputs_match_bundle_contract(self) -> None:
        """書き出すファイルが .app の ProviderLogos の 6 ファイルと一致する。"""
        names = set(self.lock["files"]) | set(self.lock["local"])
        names.add(Path(self.lock["license"]).name)
        self.assertEqual(names, BUNDLED_LOGOS | {"LICENSE-lobe-icons.txt"})

    def test_local_logos_are_normalized(self) -> None:
        """自作のロゴは、正規化した形のまま置いてある。"""
        for name in self.lock["local"]:
            with self.subTest(name=name):
                data = (ROOT / logos.LOCAL_LOGO_DIR / name).read_bytes()
                self.assertEqual(logos.normalize_svg(data, name), data)

    def test_pixellab_keeps_size_and_nonzero(self) -> None:
        """自作の pixellab.svg は 24x19.2 で、塗りの規則は既定 (nonzero) のまま。"""
        data = (ROOT / logos.LOCAL_LOGO_DIR / "pixellab.svg").read_bytes()
        header = (
            b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 19.2"'
            b' width="24" height="19.2"><path d="M'
        )
        self.assertTrue(data.startswith(header))
        self.assertTrue(data.endswith(b' fill="#000000"/></svg>\n'))
        self.assertEqual(data.count(b"<path "), 1)
        self.assertNotIn(b"fill-rule", data)

    def test_license_text(self) -> None:
        """ライセンスに MIT の本文と商標の注記がある。"""
        text = (ROOT / self.lock["license"]).read_text(encoding="utf-8")
        self.assertTrue(text.startswith("MIT License\n\nCopyright (c) 2023 LobeHub\n"))
        self.assertIn('THE SOFTWARE IS PROVIDED "AS IS"', text)
        self.assertIn("trademarks of their respective owners", text)


class LockValidationTests(unittest.TestCase):
    """壊れた lock を拒否する。"""

    def setUp(self) -> None:
        """正しい lock を用意する。"""
        self.lock = {
            "package": "@example/icons",
            "version": "1.2.3",
            "base_url": "https://cdn.example.invalid/@example/icons@1.2.3/icons/",
            "license": "Resources/LICENSE-example.txt",
            "files": {"remote.svg": "0" * 64},
            "local": ["local.svg"],
        }

    def assert_invalid(self, **changes: object) -> None:
        """一部を変えた lock が SetupError になることを確かめる。"""
        with self.assertRaises(SetupError):
            logos.validate_lock({**self.lock, **changes}, ROOT)

    def test_accepts_valid_lock(self) -> None:
        """正しい lock は通る。"""
        logos.validate_lock(self.lock, ROOT)

    def test_rejects_unpinned_version(self) -> None:
        """版を固定していない version と base_url を拒否する。"""
        base = "https://cdn.example.invalid/@example/icons"
        for version in ("latest", "^1.2.3", "1.2", "1.x"):
            with self.subTest(version=version):
                url = f"{base}@{version}/icons/"
                self.assert_invalid(version=version, base_url=url)
        for url in (
            f"{base}/icons/",
            f"{base}@latest/icons/",
            "http://cdn.example.invalid/@example/icons@1.2.3/icons/",
            f"{base}@1.2.3/icons",
        ):
            with self.subTest(base_url=url):
                self.assert_invalid(base_url=url)

    def test_rejects_bad_names_and_hashes(self) -> None:
        """使えないファイル名とハッシュの形を拒否する。"""
        for name in ("../remote.svg", "Remote.svg", "remote.png", "sub/remote.svg"):
            with self.subTest(name=name):
                self.assert_invalid(files={name: "0" * 64})
        for digest in ("0" * 63, "A" * 64, None):
            with self.subTest(digest=digest):
                self.assert_invalid(files={"remote.svg": digest})
        self.assert_invalid(files={})
        self.assert_invalid(local=["../local.svg"])
        self.assert_invalid(local=["remote.svg"])
        self.assert_invalid(local=["local.svg", "local.svg"])

    def test_rejects_license_outside_repository(self) -> None:
        """リポジトリの外を指す license を拒否する。"""
        self.assert_invalid(license="../LICENSE")
        self.assert_invalid(license="/etc/hosts")

    def test_rejects_missing_or_extra_keys(self) -> None:
        """キーの過不足を拒否する。"""
        missing = {key: value for key, value in self.lock.items() if key != "local"}
        with self.assertRaises(SetupError):
            logos.validate_lock(missing, ROOT)
        self.assert_invalid(extra="x")


class PipelineTests(unittest.TestCase):
    """取得・照合・書き出しの流れ (取得はモックに差し替える)。"""

    def setUp(self) -> None:
        """一時ディレクトリに、合成したロゴを使うリポジトリを作る。"""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name)
        self.root, self.cache, self.dest = base / "repo", base / "cache", base / "dest"
        self.remote = LOBEHUB_SHAPED
        local_source = _svg(_path("M0 0h24v19.2H0z"), 'viewBox="0 0 24 19.2"')
        self.local = logos.normalize_svg(local_source, "local")
        self.lock = {
            "package": "@example/icons",
            "version": "1.2.3",
            "base_url": "https://cdn.example.invalid/@example/icons@1.2.3/icons/",
            "license": "Resources/LICENSE-example.txt",
            "files": {"remote.svg": hashlib.sha256(self.remote).hexdigest()},
            "local": ["local.svg"],
        }
        self.url = self.lock["base_url"] + "remote.svg"
        self._write(logos.LOCK_PATH, json.dumps(self.lock).encode())
        self._write(logos.LOCAL_LOGO_DIR / "local.svg", self.local)
        self._write(Path("Resources/LICENSE-example.txt"), b"Example License\n")
        # 取得を差し替え忘れたテストがネットワークに出ないよう、既定では失敗させる。
        patcher = mock.patch.object(
            logos.urllib.request, "urlopen", side_effect=AssertionError("network")
        )
        self.urlopen = patcher.start()
        self.addCleanup(patcher.stop)

    def _write(self, relative: Path, data: bytes) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def _write_cache(self, data: bytes) -> None:
        self.cache.mkdir(parents=True, exist_ok=True)
        (self.cache / "remote.svg").write_bytes(data)

    def serve(self, body: bytes) -> None:
        """取得の応答を body にする。"""
        self.urlopen.side_effect = lambda *_args, **_kwargs: io.BytesIO(body)

    def run_main(self, *arguments: str) -> tuple[int, str, str]:
        """キャッシュの場所を渡して main を実行する。

        Returns:
            終了コード、標準出力、標準エラーの組。

        """
        stdout, stderr = io.StringIO(), io.StringIO()
        argv = ["--cache-dir", str(self.cache), *arguments]
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = logos.main(argv, root=self.root)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_downloads_verifies_and_writes(self) -> None:
        """取得したファイルを照合し、正規化した SVG とライセンスを書き出す。"""
        self.serve(self.remote)
        code, _, stderr = self.run_main("--dest", str(self.dest))
        self.assertEqual((code, stderr), (0, ""))
        written = sorted(path.name for path in self.dest.iterdir())
        self.assertEqual(written, ["LICENSE-example.txt", "local.svg", "remote.svg"])
        normalized = logos.normalize_svg(self.remote, "test")
        self.assertEqual((self.dest / "remote.svg").read_bytes(), normalized)
        self.assertEqual((self.dest / "local.svg").read_bytes(), self.local)
        license_text = (self.dest / "LICENSE-example.txt").read_bytes()
        self.assertEqual(license_text, b"Example License\n")
        self.assertEqual((self.cache / "remote.svg").read_bytes(), self.remote)
        for path in self.dest.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)
        request = self.urlopen.call_args.args[0]
        self.assertEqual(request.full_url, self.url)
        self.assertEqual(self.urlopen.call_args.kwargs["timeout"], 30)

    def test_reuses_cache_without_network(self) -> None:
        """照合できたキャッシュがあれば取得しない。"""
        self._write_cache(self.remote)
        code, _, stderr = self.run_main("--dest", str(self.dest))
        self.assertEqual((code, stderr), (0, ""))
        self.urlopen.assert_not_called()

    def test_replaces_stale_cache(self) -> None:
        """Lock と一致しないキャッシュは取り直して置き換える。"""
        self._write_cache(b"stale")
        self.serve(self.remote)
        code, stdout, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("取り直す", stdout)
        self.assertEqual((self.cache / "remote.svg").read_bytes(), self.remote)

    def test_without_dest_only_fills_cache(self) -> None:
        """書き出し先を渡さなければ、キャッシュの取得と照合だけを行う。"""
        self.serve(self.remote)
        code, _, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertFalse(self.dest.exists())
        self.assertEqual(os.listdir(self.cache), ["remote.svg"])

    def test_hash_mismatch_names_url_without_traceback(self) -> None:
        """取得したファイルが lock と違えば、URL を添えて止め、何も書かない。"""
        self.serve(self.remote.replace(b"Example", b"Changed"))
        code, _, stderr = self.run_main("--dest", str(self.dest))
        self.assertEqual(code, 1)
        self.assertIn(self.url, stderr)
        self.assertIn("SHA-256", stderr)
        self.assertNotIn("Traceback", stderr)
        self.assertFalse(self.dest.exists())
        self.assertFalse((self.cache / "remote.svg").exists())

    def test_network_errors_name_url_without_traceback(self) -> None:
        """通信の失敗は、URL を添えた 1 行のエラーにする。"""
        cases = {
            "offline": urllib.error.URLError("offline"),
            "HTTP 404 Not Found": urllib.error.HTTPError(
                self.url, 404, "Not Found", None, None
            ),
            "TimeoutError: timed out": TimeoutError("timed out"),
            "IncompleteRead": http.client.IncompleteRead(b"partial"),
        }
        for fragment, error in cases.items():
            with self.subTest(error=fragment):
                self.urlopen.side_effect = error
                code, _, stderr = self.run_main("--dest", str(self.dest))
                self.assertEqual(code, 1)
                self.assertIn(self.url, stderr)
                self.assertIn(fragment, stderr)
                self.assertNotIn("Traceback", stderr)
                self.assertFalse(self.dest.exists())

    def test_too_large_response_is_rejected(self) -> None:
        """大きすぎる応答は、読み切る前に止める。"""
        self.serve(b"x" * (logos.MAX_DOWNLOAD_BYTES + 1))
        code, _, stderr = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn(self.url, stderr)
        self.assertIn("超えた", stderr)

    def test_dest_replaces_stale_files_and_keeps_others(self) -> None:
        """書き出し先の同名のファイルは置き換え、ほかのファイルには触れない。"""
        self.dest.mkdir()
        (self.dest / "remote.svg").write_bytes(b"old")
        (self.dest / "keep.txt").write_bytes(b"keep")
        self._write_cache(self.remote)
        code, _, _ = self.run_main("--dest", str(self.dest))
        self.assertEqual(code, 0)
        normalized = logos.normalize_svg(self.remote, "test")
        self.assertEqual((self.dest / "remote.svg").read_bytes(), normalized)
        self.assertEqual((self.dest / "keep.txt").read_bytes(), b"keep")
        written = sorted(path.name for path in self.dest.iterdir())
        expected = ["LICENSE-example.txt", "keep.txt", "local.svg", "remote.svg"]
        self.assertEqual(written, expected)

    def test_unnormalized_local_logo_fails_before_writing(self) -> None:
        """自作のロゴが正規化した形でなければ、何も書かずに止める。"""
        self._write(logos.LOCAL_LOGO_DIR / "local.svg", _svg(_path()))
        self._write_cache(self.remote)
        code, _, stderr = self.run_main("--dest", str(self.dest))
        self.assertEqual(code, 1)
        self.assertIn("正規化した形になっていない", stderr)
        self.assertFalse(self.dest.exists())

    def test_rejected_remote_logo_fails_before_writing(self) -> None:
        """取得したロゴに使えない要素があれば、何も書かずに止める。"""
        bad = _svg('<image href="https://example.com/a.png"/>' + _path())
        self.lock["files"]["remote.svg"] = hashlib.sha256(bad).hexdigest()
        self._write(logos.LOCK_PATH, json.dumps(self.lock).encode())
        self._write_cache(bad)
        code, _, stderr = self.run_main("--dest", str(self.dest))
        self.assertEqual(code, 1)
        self.assertIn(self.url, stderr)
        self.assertIn("<image>", stderr)
        self.assertFalse(self.dest.exists())

    def test_cache_dir_resolution(self) -> None:
        """キャッシュの置き場所は、--cache-dir・環境変数・既定値の順に決める。"""
        environment = {logos.CACHE_DIR_ENV: "/tmp/from-env"}
        with mock.patch.dict(os.environ, environment):
            self.assertEqual(logos.resolve_cache_dir(None), Path("/tmp/from-env"))
            argument = Path("/tmp/from-argument")
            self.assertEqual(logos.resolve_cache_dir(argument), argument)
        with mock.patch.dict(os.environ, {logos.CACHE_DIR_ENV: ""}):
            default = Path("~/.cache/ignitero-launcher/provider-logos").expanduser()
            self.assertEqual(logos.resolve_cache_dir(None), default)


if __name__ == "__main__":
    unittest.main()
