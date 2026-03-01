#!/usr/bin/env python3
"""複数の絵文字キーワードデータソースを統合し、検索辞書を生成するスクリプト。

以下のソースをマージし、重複を排除して emoji_keywords_ja.json を生成する:
  1. emojibase-data ja/data.json      — 日本語 label + tags (CLDR ベース)
  2. emojibase-data en/data.json      — 英語 label + tags
  3. emoji-ja (yagays)                — 日本語口語キーワード
  4. emojilib (muan)                  — 英語口語キーワード
  5. emojibase shortcodes/github.json — GitHub shortcode
  6. emojibase shortcodes/cldr-native — 日本語ネイティブ shortcode

Usage:
    python3 scripts/update_emoji_keywords.py
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

# --- Data Source URLs ---

EMOJIBASE_JA_URL = "https://cdn.jsdelivr.net/npm/emojibase-data@latest/ja/data.json"
EMOJIBASE_EN_URL = "https://cdn.jsdelivr.net/npm/emojibase-data@latest/en/data.json"
EMOJI_JA_URL = (
    "https://raw.githubusercontent.com/yagays/emoji-ja/master/data/emoji_ja.json"
)
EMOJILIB_URL = "https://cdn.jsdelivr.net/npm/emojilib@latest/dist/emoji-en-US.json"
GITHUB_SHORTCODES_URL = (
    "https://cdn.jsdelivr.net/npm/emojibase-data@latest/en/shortcodes/github.json"
)
CLDR_NATIVE_SHORTCODES_URL = (
    "https://cdn.jsdelivr.net/npm/emojibase-data@latest/ja/shortcodes/cldr-native.json"
)

OUTPUT_PATH = (
    Path(__file__).parent.parent
    / "Sources"
    / "IgniteroCore"
    / "Resources"
    / "emoji_keywords_ja.json"
)


def fetch_json(url: str) -> dict | list:
    """URL から JSON をダウンロードする。

    Returns:
        パースされた JSON データ。
    """
    print(f"  Downloading {url.split('/')[-1]} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "ignitero-launcher/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _remove_vs(s: str) -> str:
    """Variation Selector (U+FE0F, U+FE0E) を除去する。

    Returns:
        VS を除去した文字列。
    """
    return s.replace("\ufe0f", "").replace("\ufe0e", "")


def merge_variation_selectors(data: dict[str, list[str]]) -> dict[str, list[str]]:
    """VS あり/なしのエントリを VS なしの正規形にマージする。

    Returns:
        VS なしキーのみの辞書。キーワードは重複排除済み。
    """
    merged: dict[str, list[str]] = {}
    for emoji, keywords in data.items():
        canonical = _remove_vs(emoji)
        existing = merged.get(canonical, [])
        seen: set[str] = set(existing)
        for kw in keywords:
            if kw not in seen:
                seen.add(kw)
                existing.append(kw)
        merged[canonical] = existing
    return merged


def add_keywords(
    result: dict[str, list[str]], emoji: str, new_keywords: list[str]
) -> None:
    """絵文字にキーワードを追加する（重複排除、大文字小文字無視、順序保持）。"""
    if not new_keywords:
        return
    existing = result.get(emoji, [])
    seen: set[str] = {kw.lower() for kw in existing}
    for kw in new_keywords:
        # リストが混入している場合はフラット化
        if isinstance(kw, list):
            for sub in kw:
                _add_single(sub, seen, existing)
        else:
            _add_single(kw, seen, existing)
    if existing:
        result[emoji] = existing


def _add_single(kw: str, seen: set[str], existing: list[str]) -> None:
    """単一のキーワードを重複チェック付きで追加する。"""
    if not isinstance(kw, str):
        return
    lower = kw.strip().lower()
    if not lower:
        return
    if lower not in seen:
        seen.add(lower)
        existing.append(lower)


def shortcode_to_keywords(code: str) -> list[str]:
    """shortcode 文字列からキーワードを抽出する。

    例: "grinning_face_with_smiling_eyes" -> ["grinning face with smiling eyes"]
         "thumbsup" -> ["thumbsup"]
         "+1" -> ["+1"]

    Returns:
        抽出されたキーワードのリスト。
    """
    result = [code.replace("_", " ")] if "_" in code else []
    if code not in result:
        result.insert(0, code)
    return [w for w in result if w.strip()]


def process_emojibase(
    ja_data: list[dict], en_data: list[dict], result: dict[str, list[str]]
) -> None:
    """emojibase ja/en の label + tags を統合する。"""
    print("[1/6] emojibase ja/data.json")
    # 英語データを hexcode でインデックス
    en_by_hex: dict[str, dict] = {}
    for item in en_data:
        hx = item.get("hexcode", "")
        if hx:
            en_by_hex[hx] = item

    for item in ja_data:
        emoji = item.get("emoji", "")
        if not emoji:
            continue
        hexcode = item.get("hexcode", "")

        kw: list[str] = []
        # 日本語
        label_ja = item.get("label", "")
        if label_ja:
            kw.append(label_ja)
        kw.extend(item.get("tags", []))

        # 英語
        en_item = en_by_hex.get(hexcode, {})
        label_en = en_item.get("label", "")
        if label_en:
            kw.append(label_en)
        kw.extend(en_item.get("tags", []))

        # emoticon (顔文字)
        emoticon = item.get("emoticon")
        if emoticon:
            kw.append(emoticon)
        en_emoticon = en_item.get("emoticon")
        if en_emoticon and en_emoticon != emoticon:
            kw.append(en_emoticon)

        add_keywords(result, emoji, kw)

    print(f"  -> {len(result)} entries")


def process_emoji_ja(data: dict, result: dict[str, list[str]]) -> None:
    """emoji-ja (yagays) のキーワードを統合する。"""
    print("[3/6] emoji-ja (yagays)")
    count = 0
    for emoji, info in data.items():
        kw = info.get("keywords", [])
        short_name = info.get("short_name", "")
        all_kw = []
        if short_name:
            all_kw.append(short_name)
        all_kw.extend(kw)
        if all_kw:
            add_keywords(result, emoji, all_kw)
            count += 1
    print(f"  -> merged {count} entries")


def process_emojilib(data: dict, result: dict[str, list[str]]) -> None:
    """emojilib (muan) のキーワードを統合する。"""
    print("[4/6] emojilib (muan)")
    count = 0
    for emoji, keywords in data.items():
        if keywords:
            add_keywords(result, emoji, keywords)
            count += 1
    print(f"  -> merged {count} entries")


def process_shortcodes(
    data: dict, result: dict[str, list[str]], label: str, index: int
) -> None:
    """shortcode データからキーワードを抽出して統合する。

    emojibase の shortcode JSON は hexcode -> shortcode(s) のマッピング。
    hexcode から絵文字文字列を引くために、result の既存エントリと
    emojibase データの hexcode → emoji マッピングを利用する。
    """
    print(f"[{index}/6] {label}")
    # data は hexcode -> shortcode or [shortcodes] のマッピング
    # hexcode → emoji の逆引きが必要なので、後で hex_to_emoji を渡す
    count = 0
    for _hexcode, codes in data.items():
        if isinstance(codes, str):
            codes = [codes]
        for code in codes:
            kw = shortcode_to_keywords(code)
            if kw:
                count += len(kw)
    print(f"  -> {count} shortcode keywords extracted")


def process_shortcodes_with_hex_map(
    data: dict,
    hex_to_emoji: dict[str, str],
    result: dict[str, list[str]],
    label: str,
    index: int,
) -> None:
    """shortcode データを hexcode → emoji マッピングを使って統合する。"""
    print(f"[{index}/6] {label}")
    count = 0
    for hexcode, codes in data.items():
        emoji = hex_to_emoji.get(hexcode)
        if not emoji:
            continue
        if isinstance(codes, str):
            codes = [codes]
        all_kw: list[str] = []
        for code in codes:
            all_kw.extend(shortcode_to_keywords(code))
        if all_kw:
            add_keywords(result, emoji, all_kw)
            count += 1
    print(f"  -> merged {count} entries")


def main() -> None:
    print("=== Emoji Keywords Update ===\n")
    print("Fetching data sources...")

    # ダウンロード
    ja_data = fetch_json(EMOJIBASE_JA_URL)
    en_data = fetch_json(EMOJIBASE_EN_URL)
    emoji_ja_data = fetch_json(EMOJI_JA_URL)
    emojilib_data = fetch_json(EMOJILIB_URL)
    github_sc_data = fetch_json(GITHUB_SHORTCODES_URL)
    cldr_native_sc_data = fetch_json(CLDR_NATIVE_SHORTCODES_URL)

    print("\nAll downloads complete.\n")

    # hexcode → emoji マッピングを構築（emojibase ja から）
    hex_to_emoji: dict[str, str] = {}
    for item in ja_data:
        hx = item.get("hexcode", "")
        emoji = item.get("emoji", "")
        if hx and emoji:
            hex_to_emoji[hx] = emoji

    # 統合
    result: dict[str, list[str]] = {}

    process_emojibase(ja_data, en_data, result)
    print("[2/6] emojibase en/data.json (included in step 1)")
    process_emoji_ja(emoji_ja_data, result)
    process_emojilib(emojilib_data, result)
    process_shortcodes_with_hex_map(
        github_sc_data, hex_to_emoji, result, "GitHub shortcodes", 5
    )
    process_shortcodes_with_hex_map(
        cldr_native_sc_data, hex_to_emoji, result, "CLDR native shortcodes (ja)", 6
    )

    # Variation Selector (U+FE0F, U+FE0E) を除去して正規化し、
    # VS あり/なしのキーワードをマージする。出力は VS なしの正規形のみ。
    result = merge_variation_selectors(result)

    # Compact JSON
    output = json.dumps(result, ensure_ascii=False, separators=(",", ":"))

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(output, encoding="utf-8")

    # 統計
    total_keywords = sum(len(v) for v in result.values())
    avg_keywords = total_keywords / len(result) if result else 0

    print("\n=== Result ===")
    print(f"  Output:     {OUTPUT_PATH}")
    print(f"  Entries:    {len(result)}")
    print(f"  Keywords:   {total_keywords:,} total ({avg_keywords:.1f} avg/emoji)")
    print(f"  Size:       {len(output):,} bytes")

    # サンプル表示
    samples = [
        "\U0001f44d",  # 👍
        "\U0001f600",  # 😀
        "\u2764",  # ❤
        "\U0001f525",  # 🔥
        "\U0001f389",  # 🎉
        "\U0001f35c",  # 🍜
        "\U0001f680",  # 🚀
    ]
    print("\nSamples:")
    for s in samples:
        if s in result:
            kw = result[s]
            display = kw[:10]
            suffix = f" ... +{len(kw) - 10} more" if len(kw) > 10 else ""
            print(f"  {s}: {display}{suffix}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
