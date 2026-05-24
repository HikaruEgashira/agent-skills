# pmf — PMF Engineering Audit Harness

> Audit a dev tool / OSS for **product-market fit** before you launch it. Not "does it work" — **does it stick**.

PMF はエンジニアリングで測れる。dev tool に限れば、採用は測れる3量の積に分解できる:

```
PMF readiness ≈ TTFV を超えて到達する確率
                × 価値を信用し続ける確率
                × 価値が自分ごとになる鋭さ
```

積なので、どれか1つが 0 に近いと他が満点でも採用は起きない。この harness は3次元を独立に採点し、**最弱の次元を最優先で潰す**。

## 構成(agent team)

| agent (who) | skill (how) | 監査する次元 |
|-------------|-------------|--------------|
| `ttfv-auditor` | `ttfv-audit` | Time-to-First-Value — install から本物の結果までの秒数。引数ゼロで動くか、失敗パスが次の手を示すか、価値を借りているか |
| `trust-calibrator` | `trust-audit` | 信頼 — false-positive economics、Indeterminate verdict、audit-first rollout、suppression、FP feedback loop |
| `wedge-scoper` | `wedge-audit` | scope — 鋭い楔が再利用可能な深い engine を front する構造か(libghostty パターン) |

オーケストレーター skill `pmf-audit` が3 agent をチームで起動し、次元間の相互作用(scope→TTFV、scope→FP、初回出力→信頼)を共有させ、合成 PMF readiness スコアと優先度付き改善提案を1レポートに統合する。

## 使い方

```
cd <監査したい repo>
# 「この OSS を PMF 観点で監査して」「launch 前に TTFV/trust/wedge を採点して」
```

`pmf-audit` skill が発火し、`_workspace/` に各次元の監査と最終 `pmf_report.md` を出力する。

## 設計の出自

この harness の doctrine は3つの実 OSS から抽出した: gh-verify(`resolve_repo` の推測 ladder、`--audit` rollout、`--exclude` suppression)、libverify(`Indeterminate` verdict、engine としての深さ)、parsentry(`| claude -p` で価値を借りる、`npx skills add` で install を消す)。各 audit skill はこれらを worked example として埋め込んでいる。

## Change log

| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-05-24 | initial build | all | PMF エンジニアリング doctrine を実行可能な agent team に結晶化 |
