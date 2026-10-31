"""AI 利用枠に出すプロバイダーのロゴ (SVG) を、検証・正規化して用意する。

第三者のブランドの SVG はリポジトリに入れない。OCR モデルと同じく、取得元の版と
生のファイルの SHA-256 を Resources/provider-logos.lock.json に固定し、
ビルドのたびに照合する。

- lock の files: npm パッケージの版を固定した URL から取得し、SHA-256 を
  照合してから解析する。照合できたファイルはキャッシュに置いて再利用する。
- lock の local: 自作のロゴ。正規化済みの形で Resources/ProviderLogos/ にある。

どちらも同じ検証器に通す。受け付けるのは svg・title・path の要素と、要素ごとに
決めた属性だけで、それ以外 (g・use・image・script・style・defs・
グラデーション・変形・外部参照など) はエラーにする。版を上げたときに
想定外の内容を通さないため。

書き出す SVG では path の d を一字も変えず、width / height を viewBox の
幅と高さにする (lobehub の SVG は "1em" のため、NSImage が大きさを 1x1 と
報告する)。塗りは #000000 にそろえ、title は落とす。

使い方 (--cache-dir の既定は $PROVIDER_LOGO_CACHE_DIR、未設定なら
~/.cache/ignitero-launcher/provider-logos):

    # 取得と照合だけを行う
    python3 scripts/setup_provider_logos.py [--cache-dir DIR]
    # 正規化した SVG とライセンスを DIR へ書き出す
    python3 scripts/setup_provider_logos.py [--cache-dir DIR] --dest DIR
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import NoReturn
from xml.parsers import expat

ROOT = Path(__file__).resolve().parent.parent
LOCK_PATH = Path("Resources/provider-logos.lock.json")
LOCAL_LOGO_DIR = Path("Resources/ProviderLogos")
LOCK_KEYS = ("package", "version", "base_url", "license", "files", "local")

CACHE_DIR_ENV = "PROVIDER_LOGO_CACHE_DIR"
DEFAULT_CACHE_DIR = "~/.cache/ignitero-launcher/provider-logos"
DOWNLOAD_TIMEOUT_SECONDS = 30
# ロゴは 1 枚数 KB。大きく超える応答は取得元の異常とみなし、読み切る前に止める。
MAX_DOWNLOAD_BYTES = 1024 * 1024
USER_AGENT = "ignitero-launcher (scripts/setup_provider_logos.py)"

SVG_NAMESPACE = "http://www.w3.org/2000/svg"
# 要素ごとに受け付ける属性。ここに無い要素と属性はすべて拒否する。
ALLOWED_ATTRIBUTES = {
    "svg": frozenset({"viewBox", "width", "height", "fill", "fill-rule", "style"}),
    "title": frozenset(),
    "path": frozenset({"d", "fill", "fill-rule"}),
}
# (親, 子) の組。ルートは svg だけで、title と path はその直下にだけ置ける。
ALLOWED_PLACEMENTS = frozenset({(None, "svg"), ("svg", "title"), ("svg", "path")})
# ルートの style で受け付けるプロパティ。lobehub が HTML に埋め込むときの
# 配置用に付けているもので、SVG の描画には効かない。
# 描画に効くもの (fill・transform など) は拒否する。
ALLOWED_STYLE_PROPERTIES = frozenset({"flex", "line-height"})
# 塗りの色は捨てて #000000 にそろえるため、単色だけを受け付ける
# (none や url(#...) によるグラデーションの参照は拒否する)。
FILL_PATTERN = re.compile(r"currentColor|#[0-9A-Fa-f]{3}|#[0-9A-Fa-f]{6}")
FILL_RULES = frozenset({"nonzero", "evenodd"})
XML_WHITESPACE = " \t\r\n"
VIEW_BOX_SEPARATOR = re.compile(r"[ \t\r\n,]+")
VIEW_BOX_NUMBER = re.compile(r"-?\d+(?:\.\d+)?")
# パスデータに現れる文字だけを許す。d を属性値へそのまま書き戻せることも
# これで保証する (引用符・< ・& を含まない)。
PATH_DATA_PATTERN = re.compile(
    r"[ \t\r\n]*[Mm][MmZzLlHhVvCcSsQqTtAa0-9eE.,+\- \t\r\n]*"
)
LOGO_NAME_PATTERN = re.compile(r"[a-z0-9][a-z0-9-]*\.svg")
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+")


class SetupError(Exception):
    """利用者に伝えるエラー。main がトレースバックを付けずに表示する。"""


def normalize_svg(data: bytes, source: str) -> bytes:
    """SVG を検証し、正規化した形に書き直す。

    Returns:
        正規化した SVG のバイト列。path の d は元の表記のまま残す。

    Raises:
        SetupError: 受け付けない要素・属性・値があるとき。

    """
    root, paths = _read_svg(data, source)
    view_box = _view_box(root.get("viewBox"), source)
    _check_style(root.get("style"), source)
    root_fill_rule = _fill_rule(root, "svg", source)
    if not paths:
        raise SetupError(f"{source}: path が 1 つも無い")
    width, height = view_box[2], view_box[3]
    view_box_text = " ".join(view_box)
    header = f'viewBox="{view_box_text}" width="{width}" height="{height}"'
    parts = [f'<svg xmlns="{SVG_NAMESPACE}" {header}>']
    for attributes in paths:
        d = attributes.get("d")
        if d is None:
            raise SetupError(f"{source}: d の無い path がある")
        if not PATH_DATA_PATTERN.fullmatch(d):
            raise SetupError(f"{source}: パスデータとして読めない d: {d[:40]!r}")
        # path 自身の指定が、親 (svg) から継承した指定より優先される。
        fill_rule = _fill_rule(attributes, "path", source) or root_fill_rule
        evenodd = ' fill-rule="evenodd"' if fill_rule == "evenodd" else ""
        parts.append(f'<path d="{d}" fill="#000000"{evenodd}/>')
    parts.append("</svg>\n")
    return "".join(parts).encode("utf-8")


def _read_svg(data: bytes, source: str) -> tuple[dict[str, str], list[dict[str, str]]]:
    """XML として読み、要素と属性の名前、要素の置き場所を確かめる。

    DOCTYPE (エンティティの展開と外部参照の入口) と処理命令
    (xml-stylesheet による外部 CSS など) も拒否する。

    Returns:
        ルートの属性と、path の属性 (文書順) の組。

    Raises:
        SetupError: XML として読めないとき、受け付けない要素・属性があるとき。

    """
    parser = expat.ParserCreate(namespace_separator=" ")
    parser.buffer_text = True
    parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
    stack: list[str] = []
    root: dict[str, str] = {}
    paths: list[dict[str, str]] = []

    def fail(message: str) -> NoReturn:
        raise SetupError(f"{source}:{parser.CurrentLineNumber}: {message}")

    def start(name: str, attributes: dict[str, str]) -> None:
        namespace, _, element = name.rpartition(" ")
        if namespace != SVG_NAMESPACE:
            fail(f"<{element}> が SVG の名前空間 ({SVG_NAMESPACE}) に属していない")
        if element not in ALLOWED_ATTRIBUTES:
            fail(f"<{element}> は使えない要素 (使えるのは svg・title・path だけ)")
        parent = stack[-1] if stack else None
        if (parent, element) not in ALLOWED_PLACEMENTS:
            place = f"<{parent}> の中" if parent else "ルート"
            fail(f"<{element}> は{place}に置けない")
        for attribute in attributes:
            if attribute not in ALLOWED_ATTRIBUTES[element]:
                fail(f"<{element}> の属性 {_attribute_label(attribute)} は使えない")
        if element == "svg":
            root.update(attributes)
        elif element == "path":
            paths.append(attributes)
        stack.append(element)

    def text(content: str) -> None:
        # title の文字列は捨てる。それ以外の場所に文字列があれば拒否する。
        if stack and stack[-1] == "title":
            return
        if content.strip(XML_WHITESPACE):
            fail(f"要素の外に文字列がある: {content.strip()[:40]!r}")

    def doctype(*_: object) -> None:
        fail("DOCTYPE は使えない")

    def instruction(target: str, _data: str) -> None:
        fail(f"処理命令 <?{target} ...?> は使えない")

    parser.StartElementHandler = start
    parser.EndElementHandler = lambda _name: stack.pop()
    parser.CharacterDataHandler = text
    parser.StartDoctypeDeclHandler = doctype
    parser.ProcessingInstructionHandler = instruction
    try:
        parser.Parse(data, True)
    except expat.ExpatError as error:
        reason = expat.ErrorString(error.code)
        raise SetupError(
            f"{source}:{error.lineno}: XML として読めない ({reason})"
        ) from None
    return root, paths


def _attribute_label(name: str) -> str:
    """名前空間付きの属性名 (expat は "URI 名前" で渡す) を読める形にする。

    Returns:
        エラーの文面に出す属性名。

    """
    namespace, _, local = name.rpartition(" ")
    return f"{local} (名前空間 {namespace})" if namespace else local


def _view_box(value: str | None, source: str) -> tuple[str, str, str, str]:
    """ルートの viewBox を 4 つの数値に分ける。

    Returns:
        min-x・min-y・幅・高さ。数値は元の表記のまま返す。

    Raises:
        SetupError: viewBox が無い、4 つの数値でない、幅か高さが 0 以下のとき。

    """
    if value is None:
        raise SetupError(f"{source}: <svg> に viewBox が無い")
    numbers = VIEW_BOX_SEPARATOR.split(value.strip(XML_WHITESPACE))
    if len(numbers) != 4 or not all(VIEW_BOX_NUMBER.fullmatch(n) for n in numbers):
        raise SetupError(f'{source}: viewBox="{value}" が 4 つの数値になっていない')
    if float(numbers[2]) <= 0 or float(numbers[3]) <= 0:
        raise SetupError(f'{source}: viewBox="{value}" の幅と高さが正の数でない')
    return numbers[0], numbers[1], numbers[2], numbers[3]


def _check_style(value: str | None, source: str) -> None:
    """ルートの style が、描画に効かないプロパティだけでできているか確かめる。

    Raises:
        SetupError: 受け付けないプロパティがあるとき。

    """
    if value is None:
        return
    for declaration in value.split(";"):
        if not declaration.strip():
            continue
        name, colon, _ = declaration.partition(":")
        if not colon or name.strip().lower() not in ALLOWED_STYLE_PROPERTIES:
            allowed = "・".join(sorted(ALLOWED_STYLE_PROPERTIES))
            raise SetupError(
                f'{source}: <svg> の style "{declaration.strip()}" は使えない'
                f" (使えるのは {allowed} だけ)"
            )


def _fill_rule(attributes: dict[str, str], element: str, source: str) -> str | None:
    """塗りの指定 (fill と fill-rule) の値を確かめる。

    Returns:
        fill-rule の指定。無ければ None。

    Raises:
        SetupError: 単色でない fill や、nonzero・evenodd 以外の fill-rule のとき。

    """
    fill = attributes.get("fill")
    if fill is not None and not FILL_PATTERN.fullmatch(fill):
        raise SetupError(
            f'{source}: <{element}> の fill="{fill}" は使えない'
            " (currentColor か #rgb / #rrggbb の単色だけ)"
        )
    rule = attributes.get("fill-rule")
    if rule is not None and rule not in FILL_RULES:
        raise SetupError(
            f'{source}: <{element}> の fill-rule="{rule}" は使えない'
            " (nonzero か evenodd だけ)"
        )
    return rule


def load_lock(root: Path) -> dict:
    """リポジトリの lock を読み、形を確かめる。

    Returns:
        lock の内容。

    Raises:
        SetupError: 読めないとき。

    """
    try:
        lock = json.loads((root / LOCK_PATH).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SetupError(f"{LOCK_PATH} を読めない ({error})") from None
    validate_lock(lock, root)
    return lock


def validate_lock(lock: object, root: Path) -> None:
    """Lock の形を確かめる。

    版を固定していない URL や、リポジトリの外を指すパスは受け付けない。

    Raises:
        SetupError: 形が合わないとき。

    """
    if not isinstance(lock, dict) or set(lock) != set(LOCK_KEYS):
        raise SetupError(f"{LOCK_PATH}: キーは {', '.join(LOCK_KEYS)} にする")
    package, version, base_url, license_path = (
        lock[key] for key in ("package", "version", "base_url", "license")
    )
    if not all(isinstance(v, str) for v in (package, version, base_url, license_path)):
        raise SetupError(
            f"{LOCK_PATH}: package・version・base_url・license は文字列にする"
        )
    if not VERSION_PATTERN.fullmatch(version):
        raise SetupError(
            f'{LOCK_PATH}: version "{version}" は x.y.z の形で固定する'
            " (latest や範囲指定は使わない)"
        )
    pinned = f"/{package}@{version}/"
    if not (
        base_url.startswith("https://")
        and base_url.endswith("/")
        and pinned in base_url
    ):
        raise SetupError(
            f'{LOCK_PATH}: base_url は https:// で始め、"{pinned}" を含み、"/" で終える'
        )
    license_file = (root / license_path).resolve()
    if Path(license_path).is_absolute() or not license_file.is_relative_to(
        root.resolve()
    ):
        raise SetupError(
            f'{LOCK_PATH}: license "{license_path}" はリポジトリ内の相対パスにする'
        )
    files, local = lock["files"], lock["local"]
    if not isinstance(files, dict) or not files:
        raise SetupError(f"{LOCK_PATH}: files はファイル名と SHA-256 の組にする")
    if not isinstance(local, list):
        raise SetupError(f"{LOCK_PATH}: local はファイル名の配列にする")
    for name in [*files, *local]:
        if not isinstance(name, str) or not LOGO_NAME_PATTERN.fullmatch(name):
            raise SetupError(
                f"{LOCK_PATH}: ファイル名 {name!r} は英小文字・数字・ハイフンと"
                " .svg で書く"
            )
    for name, digest in files.items():
        if not isinstance(digest, str) or not SHA256_PATTERN.fullmatch(digest):
            raise SetupError(
                f"{LOCK_PATH}: {name} の SHA-256 は 16 進の小文字 64 文字で書く"
            )
    if len(set(local)) != len(local) or set(local) & set(files):
        raise SetupError(f"{LOCK_PATH}: files と local で同じファイル名を重ねない")


def download(url: str) -> bytes:
    """URL の中身を取得する。

    Returns:
        応答の本文。

    Raises:
        SetupError: 取得に失敗したとき、応答が大きすぎるとき (文面に URL を含める)。

    """
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    chunks: list[bytes] = []
    size = 0
    try:
        with urllib.request.urlopen(
            request, timeout=DOWNLOAD_TIMEOUT_SECONDS
        ) as response:
            while chunk := response.read(64 * 1024):
                size += len(chunk)
                if size > MAX_DOWNLOAD_BYTES:
                    raise SetupError(
                        f"{url} の応答が {MAX_DOWNLOAD_BYTES} バイトを超えた"
                    )
                chunks.append(chunk)
    except urllib.error.HTTPError as error:
        raise SetupError(
            f"{url} を取得できない (HTTP {error.code} {error.reason})"
        ) from None
    except urllib.error.URLError as error:
        raise SetupError(f"{url} を取得できない ({error.reason})") from None
    except (OSError, http.client.HTTPException, ValueError) as error:
        raise SetupError(
            f"{url} を取得できない ({type(error).__name__}: {error})"
        ) from None
    return b"".join(chunks)


def fetch_verified(name: str, expected: str, url: str, cache_dir: Path) -> bytes:
    """生のファイルを、lock の SHA-256 と照合してキャッシュか取得元から得る。

    キャッシュが一致しなければ取り直し、一致したものだけをキャッシュに置く。

    Returns:
        SHA-256 が一致したファイルの中身。

    Raises:
        SetupError: 取得したファイルが lock と一致しないとき。

    """
    cached = cache_dir / name
    try:
        data: bytes | None = cached.read_bytes()
    except FileNotFoundError:
        data = None
    if data is not None and hashlib.sha256(data).hexdigest() == expected:
        print(f"{name}: キャッシュを使う (SHA-256 一致)", flush=True)
        return data
    if data is not None:
        print(f"{name}: キャッシュが lock と違うため取り直す", flush=True)
    print(f"{name}: {url} から取得する", flush=True)
    data = download(url)
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected:
        raise SetupError(
            f"{url} の SHA-256 が lock と一致しない"
            f" (lock: {expected} / 取得: {actual})。"
            "版を上げるときは lock の version・base_url・files をまとめて更新する"
        )
    _write_atomic(cached, data)
    return data


def build_outputs(lock: dict, root: Path, cache_dir: Path) -> dict[str, bytes]:
    """書き出すファイルを、すべて検証してからまとめて返す。

    1 つでも検証に失敗したらその時点で止め、書き出し先には何も書かない。

    Returns:
        ファイル名と中身の組 (lock の files・local の順で、最後にライセンス)。

    Raises:
        SetupError: 自作のロゴが正規化した形でないとき、ライセンスが空のとき。

    """
    outputs: dict[str, bytes] = {}
    for name, expected in lock["files"].items():
        url = lock["base_url"] + name
        raw = fetch_verified(name, expected, url, cache_dir)
        outputs[name] = normalize_svg(raw, url)
    for name in lock["local"]:
        relative = LOCAL_LOGO_DIR / name
        data = _read_repository_file(root, relative)
        if normalize_svg(data, str(relative)) != data:
            raise SetupError(
                f"{relative} が正規化した形になっていない"
                " (normalize_svg の出力と同じバイト列にする)"
            )
        outputs[name] = data
    license_path = Path(lock["license"])
    license_text = _read_repository_file(root, license_path)
    if not license_text.strip():
        raise SetupError(f"{license_path} が空")
    outputs[license_path.name] = license_text
    return outputs


def _read_repository_file(root: Path, relative: Path) -> bytes:
    """リポジトリ内のファイルを読む。

    Returns:
        ファイルの中身。

    Raises:
        SetupError: 読めないとき。

    """
    try:
        return (root / relative).read_bytes()
    except OSError as error:
        raise SetupError(f"{relative} を読めない ({error.strerror or error})") from None


def _write_atomic(path: Path, data: bytes) -> None:
    """一時ファイルに書いてから置き換え、書きかけのファイルを残さない。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
        # mkstemp は 0600 で作る。.app を他のユーザーも読めるよう、
        # cp と同じ 0644 にする。
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def resolve_cache_dir(argument: Path | None) -> Path:
    """キャッシュの置き場所を、--cache-dir・環境変数・既定値の順に決める。

    Returns:
        キャッシュのディレクトリ。

    """
    if argument is not None:
        return argument.expanduser()
    return Path(os.environ.get(CACHE_DIR_ENV) or DEFAULT_CACHE_DIR).expanduser()


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    """コマンドラインから実行する。

    Returns:
        終了コード。失敗したときはトレースバックを出さずに 1 を返す。

    """
    parser = argparse.ArgumentParser(
        description="AI 利用枠のプロバイダーロゴを取得・照合し、正規化して書き出す。"
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        help=(
            f"取得したロゴの置き場所 (既定: ${CACHE_DIR_ENV}、"
            f"未設定なら {DEFAULT_CACHE_DIR})"
        ),
    )
    parser.add_argument(
        "--dest",
        type=Path,
        help=(
            "正規化した SVG とライセンスを書き出すディレクトリ。"
            "省略すると取得と照合だけを行う"
        ),
    )
    args = parser.parse_args(argv)
    cache_dir = resolve_cache_dir(args.cache_dir)
    try:
        outputs = build_outputs(load_lock(root), root, cache_dir)
        if args.dest is not None:
            for name, data in outputs.items():
                _write_atomic(args.dest / name, data)
    except (SetupError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.dest is None:
        print(f"プロバイダーロゴを照合した (キャッシュ: {cache_dir})")
    else:
        print(f"プロバイダーロゴを書き出した: {args.dest} ({len(outputs)} ファイル)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
