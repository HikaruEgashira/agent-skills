---
name: wedge-audit
description: |
  deep OSS の scope 戦略を監査する方法論。鋭い単一用途の楔(wedge)が再利用可能な深い engine を
  front する構造か(libghostty パターン)を採点する。楔の鋭さ・深さの隠し場所・寄生先・10x の一点を見る。
  wedge-scoper agent が使用。
  Trigger: scope 監査, wedge 監査, wedge over engine, libghostty パターン, engine shell 分離, scope creep.
user-invocable: false
---

## 監査の前提

「deep」と「adoptable」は scope を分離すれば喧嘩をやめる。深さは再利用可能な engine に隠し、ユーザーが触れる面は鋭い単一用途の楔にする。**「薄いシェル over 深いライブラリ」は本質的にディストリビューション判断**。楔の鋭さが「価値が自分ごとになる確率」を決める。

罠: 深い builder ほど「全部入り」を作りたがる。手を広げて全機能が 2x の凡庸より、1 ユースケースが 10x の鋭い楔の方が deep OSS は刺さる。

## 監査ステップ

### 1. 楔の鋭さを見る

ユーザーに見せる面が単一の鋭いユースケースか、「何でもできる」曖昧な面か。曖昧さは「これは自分の問題のためのツールだ」という認識を妨げる。

<example>
<input>gh-verify を監査</input>
<output>
楔: 「GitHub の PR/release/repo の SDLC 健全性を gh CLI 1コマンドで検査」。
単一プラットフォーム(GitHub)・単一の入口(gh extension)・明確な1動詞(verify)。
曖昧な「何でも監査」ではなく鋭い → 強い。
</output>
</example>

### 2. 深さの隠し場所を見る(engine/shell 分離)

深い実装が再利用可能な engine/core に分離され、薄い platform shell が consume する構造か。深さを楔の表面に漏らしていないか。

<example>
<input>gh-verify + libverify</input>
<output>
libverify = platform 非依存 engine、34 controls、Creusot で形式証明(README: "libghostty for SDLC")。深さの貯蔵庫。
gh-verify = 薄い GitHub shell、engine を consume するだけ。
深さは engine に隔離、楔は薄い → 教科書的に強い。別 platform shell を後から足せる拡張性も得る。
</output>
</example>

### 3. 寄生先を見る(採用摩擦)

楔が既存ワークフロー(gh CLI / npx / パイプ / editor / CI)に寄生して採用摩擦を下げているか。ゼロから新習慣を要求していないか。

<example>
<input>gh-verify / parsentry</input>
<output>
gh-verify: `gh` 拡張として寄生 → gh ユーザーは新ツール習得不要。`action.yml` で GitHub Actions にも寄生。
parsentry: `| claude -p` でエージェント CLI に寄生、`npx skills add` で skill エコシステムに寄生。
既存習慣に乗っている → 強い。
</output>
</example>

### 4. 「10x の一点」を見る

楔は「最初の鋭い1ユースケースを 10x better」にしてから広げる戦略か。最初から手を広げて全部 2x の凡庸に陥っていないか。

## スコアリング・ルーブリック (0-10)

| スコア | 状態 |
|--------|------|
| 0-2 | 「何でもできる」曖昧な面。深さが表面に漏れ、初見が用途を掴めない。新習慣を強要 |
| 3-5 | 用途は一応単一だが engine/shell が未分離(深さが楔に癒着)。寄生先なし |
| 6-7 | 鋭い楔 or engine 分離、どちらか + 既存ワークフローへの寄生 |
| 8-9 | 鋭い楔 + engine/shell 分離 + 寄生先、を満たす |
| 10 | 上記全て + 明確な「10x の一点」。engine が複数 shell に再利用され面を広げられる |

engine/shell が別 repo で片方欠如なら見える範囲で採点し欠如側を未検証と明記。

## 出力フォーマット

`_workspace/03_wedge_scoper.md` に:

```markdown
# Wedge Audit: <repo>
## スコア: N/10 — <一言根拠>
## 楔の鋭さ
<単一用途か曖昧か>
## engine / shell 分離
<どこに深さ、どこに楔。分離図>
## 寄生先
<既存ワークフローへの寄生と採用摩擦>
## 10x の一点
<最初に 10x にする鋭い1点はどこか>
## scope リスクと提案
| Severity | リスク | 位置/構成 | 提案(絞る/分離する/寄生する) |
|----------|--------|-----------|--------------------------------|
```

## アンチパターン(減点対象)

| パターン | なぜ減点 |
|----------|----------|
| 「何でもできる」面 | 自分ごと化を妨げ、誰にも刺さらない |
| 深さを楔に癒着(engine 未分離) | 拡張不能、楔が太って初回が重い |
| 新習慣を強要(寄生しない) | 採用摩擦が最大化 |
| 最初から多機能(10x の一点が無い) | 全部 2x の凡庸、差別化なし |
| engine を1 shell に密結合 | 再利用で面を広げられない |
