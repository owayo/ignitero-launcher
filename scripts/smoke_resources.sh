#!/bin/bash
# `.app` としてパッケージされた状態でリソース解決が成立しているかを検証する。
#
# `Bundle.module` は `.app` では解決できない。SwiftPM が生成する accessor の探索先は
# 「`.app/` ルート直下」と「ビルド時に焼き込まれた `.build/<triple>/<config>/` の
# 絶対パス」の 2 つだけで、`Contents/Resources` を見ない。ルート直下へ置くと codesign が
# unsealed contents として拒否するため、開発マシンでは常に後者で解決されている。
# つまり `.app` にリソースを入れ忘れても開発マシンでは動いてしまい、`.build` を消した
# ときと配布物でだけクラッシュする（2026-09-01 に絵文字検索で実際に落ちた）。
#
# そこで焼き込み先の `.bundle` を一時的にリネームして fallback を無効化し、
# `.app` 内のリソースだけで自己診断が通ることを確かめる。`.build` ごと移動すると
# 中断時に失われるため、バンドル単位でリネームする。
set -euo pipefail

APP="${1:?usage: smoke_resources.sh <path to .app>}"
EXEC_NAME="${2:-IgniteroLauncher}"
EXEC="${APP}/Contents/MacOS/${EXEC_NAME}"
SUFFIX=".smoke-hidden"

if [ ! -x "${EXEC}" ]; then
  echo "error: 実行ファイルが無い: ${EXEC}" >&2
  exit 1
fi

HIDDEN=()

# 退避したバンドルを元の名前へ戻す。
# 戻し先が既に存在する場合 (退避中に `swift build` が走って再生成された等) に
# `mv` するとディレクトリの中へ入れ子で移動してしまうため、必ず先に確認する。
unhide() {
  local hidden="$1"
  local target="${hidden%"${SUFFIX}"}"
  if [ ! -d "${hidden}" ]; then
    return 0
  fi
  if [ -e "${target}" ]; then
    echo "warning: ${target} が再生成済みのため ${hidden} を復元しなかった (手動で確認する)" >&2
    return 0
  fi
  mv "${hidden}" "${target}"
}

restore() {
  local path
  for path in "${HIDDEN[@]+"${HIDDEN[@]}"}"; do
    unhide "${path}${SUFFIX}"
  done
}
trap restore EXIT

# 前回の中断で残ったものがあれば先に戻す。
shopt -s nullglob
for leftover in .build/*/*/*.bundle"${SUFFIX}"; do
  unhide "${leftover}"
  echo "note: 前回の中断で残っていた ${leftover} を処理した"
done

for bundle in .build/*/*/*.bundle; do
  mv "${bundle}" "${bundle}${SUFFIX}"
  HIDDEN+=("${bundle}")
done
shopt -u nullglob

echo "Bundle.module の fallback を ${#HIDDEN[@]} 件退避した (.build/<triple>/<config>/*.bundle)"
echo "--- ${APP} で自己診断を実行 ---"
"${EXEC}" --self-test-resources
