---
name: pmf-audit
description: |
  dev tool / OSS が「刺さるか(PMF)」をエンジニアリング観点で監査するオーケストレーター。
  3 specialist agent (ttfv-auditor / trust-calibrator / wedge-scoper) をチームで起動し、
  初回体験(TTFV)・出力の信頼(false-positive economics)・scope の鋭さ(wedge over engine)を
  並行監査して、合成 PMF readiness スコアと優先度付き改善提案を1つのレポートに統合する。
  Trigger: PMF 監査, PMF audit, dev tool 採用, なぜ自分のOSSが採用されない, ローンチ前監査,
  TTFV, time to first value, false positive, 誤検知, 信頼設計, wedge, scope 設計,
  this tool isn't getting adopted, audit my OSS before launch, 再監査, re-audit, 改善後の再評価.
  CLI/library/dev tool/security tool の repo を渡された採用観点の監査依頼で発火する。
  単なるコードレビューやバグ探し、一般的な品質監査では発火しない(それらは別 skill)。
user-invocable: true
---

## 目的

「動くか」ではなく「**刺さるか**」を監査する。deep OSS の PMF を、測れる3量の積に分解して採点する:

```
PMF readiness ≈ TTFV を超えて到達する確率
                × 価値を信用し続ける確率
                × 価値が自分ごとになる鋭さ
```

積であることが重要: どれか1つが 0 に近いと、他が満点でも採用は起きない。だから3次元を独立に採点し、最弱の次元を最優先で潰す。

## 実行モード

**Agent team**(default)。3 agent が同一 repo を fan-out で並行監査し、次元間の相互作用(scope→TTFV、scope→FP、初回出力→信頼)を SendMessage で共有する。leader(この skill を実行する main)が結果を合成する。

## Phase 0: context チェック

監査開始時に実行モードを判定する:

- `_workspace/` が存在 + ユーザーが部分修正を依頼 → **部分再監査**(該当 agent のみ再起動)
- `_workspace/` が存在 + 新しい対象/大幅変更 → **新規監査**(旧 `_workspace/` を `_workspace_prev/` に退避してから開始)
- `_workspace/` が無い → **初回監査**

## Phase 1: 対象の特定

1. 監査対象 repo を確定する。引数に owner/repo か path があればそれ。無ければ現在の作業ディレクトリ。
2. repo の種別を判定(CLI / library / service / security tool)。種別で各 agent の重み付けが変わる(下記)。
3. `_workspace/` を作成。

**種別による重み(合成スコア計算用):** ラベルは数値に写像する — **高=2, 中=1, 低=0.5**。監査者裁量で合成スコアがブレないよう、必ずこの数値を使う。

| 種別 | TTFV | Trust | Wedge |
|------|------|-------|-------|
| CLI / dev tool | 高(2) | 中(1) | 高(2) |
| security / correctness tool | 中(1) | **高(2)** | 高(2) |
| library (engine) | 中(1) | 中(1) | 高(2) |
| service | 高(2) | 中(1) | 中(1) |

## Phase 2: チーム編成と task 割当

1. `TeamCreate` で 3 member のチームを作る: `ttfv-auditor`, `trust-calibrator`, `wedge-scoper`(全て `model: "opus"`、各 `.claude/agents/` または本 plugin の `agents/` 定義を使用)。
2. `TaskCreate` で各 agent に「対象 repo を自分の次元で監査し `_workspace/0N_*.md` に出力」を割り当てる。3 task は並行可能(依存なし)だが、相互参照フェーズで合流する。

**次元の責任境界(二重計上を防ぐ):** 「scope が広い → 誤検知面も広い」は Trust と Wedge の両方に触れる。切り分けは — **scope の広さそのもの(楔が鈍い)は Wedge の減点。広い scope が実際に FP を生んでいる証拠(誤検知の finding)があれば Trust の減点**。同じ事実を両次元で二重に引かない。

## Phase 3: 並行監査と相互参照

- 各 agent は自分の audit skill(`ttfv-audit` / `trust-audit` / `wedge-audit`)を適用して監査する。
- agent 定義の Team Communication Protocol に従い、次元間相互作用を SendMessage で共有する(例: wedge-scoper が「scope が広く初回コマンドが複雑」と判断 → ttfv-auditor へ共有 → TTFV スコア根拠に反映)。
- leader は進捗を監視し、行き詰まり(Indeterminate 多発、repo 読めない)があれば追加手がかりを供給する。

## Phase 4: 合成

3 つの `_workspace/0N_*.md` を読み、最終レポートを生成する:

1. **3 次元スコア表**(各 0-10 + 根拠 + 各次元の最重要 finding)。
2. **合成 PMF readiness**: 種別重み付き幾何平均(積モデル)。式は明示的に:

   ```
   PMF = ( Π scoreᵢ^wᵢ )^(1 / Σwᵢ)      wᵢ ∈ {高=2, 中=1, 低=0.5}
   ```

   例(security tool, TTFV=9/Trust=10/Wedge=9, 重み 1/2/2): `(9¹·10²·9²)^(1/5) = 9.4`。最弱次元を明示。幾何平均にするのは「1つの低スコアが全体を引き下げる」積の性質を保つため(算術平均だと弱点が埋もれる)。
3. **優先度付き改善提案**: Critical → Low。各提案に (a) どの次元 (b) コード位置/repo 構成 (c) 「削る/分離する/借りる」のどの動きか を付す。最弱次元の Critical/High を最上段に。
4. **「launch して良いか」の一言判定**: 合成スコアと最弱次元から、launch 可 / 楔を絞れ / 初回体験を彫れ / 信頼設計を入れろ のいずれか。

レポートは `_workspace/pmf_report.md` に保存し、要約をユーザーに提示。チームは `TeamDelete` で解散。

## データ受け渡し

- **task-based**: TaskCreate/TaskUpdate で進捗と依存。
- **file-based**: `_workspace/0N_{agent}.md`(中間)+ `_workspace/pmf_report.md`(最終)。命名は `{phase}_{agent}_{artifact}`。
- **message-based**: 次元間相互参照は SendMessage。
- 中間ファイルは監査証跡として残す。ユーザーに出すのは最終レポート。

## エラーハンドリング

- agent が監査不能 → 1度別手がかりで再試行。再失敗ならその次元を Indeterminate とし、合成スコアから除外せず「測定不能」として明示(捏造しない)。
- 次元間で結論が矛盾 → 両論をソース付きで併記。消さない。
- engine/shell が別 repo で片方欠如 → 見える範囲で監査、欠如側を未検証と明記。

## Test scenarios

**Happy path:** `cd ~/ghq/github.com/HikaruEgashira/gh-verify && (pmf-audit を発火)` → 3 agent が並行監査 → TTFV 高(resolve_repo の ladder, audit-first), Trust 高(Indeterminate verdict, --audit), Wedge 高(libverify engine + 薄い gh shell)→ 合成スコア高 +「launch 可、楔は鋭い」判定。

**Error path:** README も manifest も無い空 repo → ttfv-auditor が TTFV 測定不能を報告 → 該当次元 Indeterminate、他2次元は監査続行、レポートに測定不能の理由を明記。

**Follow-up:** 改善 commit 後の再監査依頼 → Phase 0 が `_workspace/` 検出 → `_workspace_prev/` 退避 → 新規監査 → 前回との差分をレポート冒頭に提示。

> **検証の独立性に関する警告:** 各 audit skill の `<example>` は gh-verify / libverify / parsentry を正例に使っている。これらを採点対象にすると「模範解答が印刷された試験」になり、スコアが skill 作者の事前判断をなぞっただけになる恐れがある。harness の方法論を健全に検証するなら、**example に使っていない未知の OSS** を採点せよ。example repo の高スコアは方法論の正しさの証拠にはならない。
