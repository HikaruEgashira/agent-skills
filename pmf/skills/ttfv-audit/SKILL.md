---
name: ttfv-audit
description: |
  dev tool / OSS の Time-to-First-Value(見知らぬ人が install してから本物の価値に触れるまでの秒数)を
  監査する方法論。初回ファネルを step 単位で復元し、引数ゼロで動くか・失敗パスが次の手を示すか・
  価値を借りているかを採点する。ttfv-auditor agent が使用。
  Trigger: TTFV 監査, 初回体験 監査, time to first value, onboarding friction, first-run, 採用ファネル.
user-invocable: false
---

## 監査の前提

dev tool の採用率の上限は TTFV が指数的に支配する。新規ユーザーの行動は確率過程で、各ステップで一定割合が脱落する。5 ステップで各 70% 残存なら最後まで来るのは 0.7^5 ≈ 17%。**ステップを1個消すと残存が約 1.4 倍**になる。機能を1個足すより効く。

罠: deep なツールほど default で TTFV が悪化する。深さ＝設定可能性＝初回の意思決定コスト。だから「作者が自分の深さと戦って初回体験を彫れているか」を見る。

## 監査ステップ

### 1. 初回ファネルを step 単位で復元する

README と実コードから、見知らぬ人の経路を機械的に並べる: 発見 → install → 最初のコマンド → 最初の結果。各 step を1行で書き、**本物の価値(意味のある結果)に届くまでのコマンド数**を数える。

<example>
<input>gh-verify を監査</input>
<output>
| step | 操作 | コスト |
|------|------|--------|
| 1 | `gh extension install HikaruEgashira/gh-verify` | install |
| 2 | `gh verify pr 6933 --repo expressjs/express` | 1 コマンドで本物の findings |

TTFV ≈ install + 1 コマンド。**他人の有名 repo(expressjs/express)をデモ対象に借りている** → 自分の repo を晒さず試せる。価値が即わかる。
</output>
</example>

### 2. 「引数ゼロで動くか」を見る(推測の ladder)

日常利用での最短コマンドを決めるのは、ツールが省略可能な引数をどこまで推測するか。明示 > 環境 > 文脈、の ladder の最下段が「ふつうの使い方」に据えられているかを確認する。

<example>
<input>gh-verify の repo 解決</input>
<output>
`crates/cli/src/main.rs:840` `resolve_repo`:
明示 `--repo` > 環境 `GH_REPO` > 文脈 `detect_repo_from_git_remote()`。
最下段が `git remote get-url origin` から repo を推測 → repo 内なら `gh verify pr 42` だけで動く。
**評価: ladder の底が日常利用に据えられている → 強い。**
</output>
</example>

### 3. 失敗パスを採点する(本体)

脱落が起きるのは成功パスでなく失敗パス。新規ユーザーほど想定外の文脈にいる。全 error が `[現象] + [次に打つ手] + (実例)` の型かを確認する。

<example>
<input>gh-verify のエラー</input>
<output>
`main.rs:849`: "could not resolve repo. Use --repo OWNER/REPO or set GH_REPO env var"
`main.rs:854`: "invalid repo format '{}'. Expected OWNER/REPO (e.g. cli/cli)"
両方とも [現象]+[次の手]+実例(cli/cli)。失敗を1リトライに変換 → 強い。
</output>
</example>

### 4. 「借りているか」を見る

ユーザーの世界に既にあるもの(install: npx / 文脈: git remote / 既存ツール: pipe)へ接続し、自作範囲を減らしているか。

<example>
<input>parsentry</input>
<output>
`npx skills add HikaruEgashira/parsentry` → install を消す。
`parsentry scan owner/repo | claude -p` → 分析エンジンを既存 claude から借りる。証明すべき価値を「良い prompt 生成」に絞れている → 強い。
</output>
</example>

## スコアリング・ルーブリック (0-10)

| スコア | 状態 |
|--------|------|
| 0-2 | install 後、本物の結果に届くまで複数の設定/認証/サンプル準備が必須。引数必須。エラーは現象のみ |
| 3-5 | 1 コマンドだが repo/config を毎回明示要求。失敗パスのエラーが不親切 |
| 6-7 | 引数ゼロで動く文脈推測あり or 良いエラー、どちらか。デモ対象を借りている |
| 8 | {推測 ladder, 良い失敗パス, 借りる設計} のうち**ちょうど 2 つ**を満たす |
| 9 | **3 つすべて**満たすが install が実質ゼロでない(例: extension/cargo install が必須) |
| 10 | 3 つすべて + install すら実質ゼロ(npx 等)。初見が秒で「これは凄い」に到達 |

証拠不足で測定不能なら Indeterminate(スコアを捏造しない)。

## 出力フォーマット

`_workspace/01_ttfv_auditor.md` に:

```markdown
# TTFV Audit: <repo>
## スコア: N/10 — <一言根拠>
## 初回ファネル
<step テーブル>
## 推測の ladder
<resolve 系の評価>
## 失敗パス
<エラーの型評価>
## 借りる設計
<install/文脈/pipe の評価>
## 摩擦と提案
| Severity | 摩擦 | 位置 | 提案(削る/借りる) |
|----------|------|------|----------------------|
```

## アンチパターン(監査で減点する対象)

| パターン | なぜ減点 |
|----------|----------|
| 初回に config ファイル必須 | ステップ増 = 指数的脱落 |
| 全引数 required | 日常利用の最短コマンドが伸びる |
| エラーが現象のみ(次の手なし) | 失敗パスで離脱 |
| 自前で全部抱える(借りない) | 初回到達が重くなる |
| 深さを初回に露出 | deep ほど TTFV が悪化する罠 |
