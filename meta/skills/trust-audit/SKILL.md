---
name: trust-audit
description: |
  security / correctness tool(linter, scanner, verifier)の出力が信頼を獲得・維持できる設計かを
  監査する方法論。false-positive economics、Indeterminate verdict、audit-first rollout、
  suppression の使い勝手、FP feedback loop を採点する。trust-calibrator agent が使用。
  Trigger: 信頼設計 監査, false positive 監査, FP economics, verdict 設計, audit-first, suppression, linter 疲労.
user-invocable: false
---

## 監査の前提

正しさを売るツールでは、信頼が通貨。**false positive は false negative より採用に致命的**: 1 件の誤検知が「狼少年」を生み、以降の全 finding が無視される(linter 疲労)。TTFV を超えて到達したユーザーが「価値を信用し続ける確率」を、出力設計が決める。

多くのツールは binary pass/fail を強制し、証拠不足の場面で**嘘をつく**。信頼設計とは、この嘘をつかない仕組みを持つこと。

## 監査ステップ

### 1. verdict モデルを見る(嘘をつかない設計)

出力が binary(pass/fail)か、それとも証拠不足を表現できる中間状態を持つか。証拠が無いのに「合格」と言うのは嘘であり、信頼を毀損する。

<example>
<input>libverify を監査</input>
<output>
verdict 分類: `Satisfied / Violated / Indeterminate / Not Applicable`(README, crates の registry/assessment)。
`Indeterminate` = 証拠不足を正直に表明する状態。`Not Applicable` = 対象外を明示。
binary を強制せず4値を持つ → 嘘をつかない設計 → 強い。
profile が verdict を pass/review/fail に写像(gate 判断は別レイヤ)→ 判定と gate の分離も良い。
</output>
</example>

### 2. rollout の勾配を見る(信頼を稼いでから gate へ)

初回からいきなり enforce(CI を落とす)だと、最初の FP で見捨てられる。報告のみ → 信頼獲得 → gate、の勾配があるか。

<example>
<input>gh-verify</input>
<output>
`--audit` モード = 報告するが CI を落とさない(main.rs の after_help, README Adoption Path)。
Adoption Path: Evaluate(--audit)→ Tune(--policy/--exclude)→ Enforce(--audit 外す)→ Scale。
信頼を稼いでから gate に移る勾配が明示 → 強い。
</output>
</example>

### 3. 誤検知の出口を見る(suppression の使い勝手)

FP が出たとき、ユーザーがそれを安全に・局所的に黙らせられるか。出口が無いと1件の FP がツール全体の放棄に直結する。

<example>
<input>gh-verify</input>
<output>
`--exclude <controls>` で個別 control を抑制、`--policy oss` で OSS 向けに緩和(main.rs の CommonOpts, conflicts_with で exclude/only 排他)。
誤検知を全体放棄でなく局所抑制に変換 → 強い。
</output>
</example>

### 4. FP feedback loop を見る

FP rate を観測・分類して potency を継続的に上げる機構があるか(real-world 検証、TP/FP 分類、policy/adapter/control 層での修正ループ)。

## スコアリング・ルーブリック (0-10)

| スコア | 状態 |
|--------|------|
| 0-2 | binary pass/fail のみ。証拠不足でも断定。suppression 無し。FP で即全放棄を招く |
| 3-5 | binary だが exclude はある。audit モード無し。FP 計測なし |
| 6-7 | Indeterminate 相当の中間状態 or audit-first、どちらか + suppression |
| 8-9 | 中間 verdict + audit-first rollout + 局所 suppression を満たす |
| 10 | 上記全て + FP feedback loop で potency を継続改善。判定と gate を分離 |

出力 finding を持たない純ライブラリ等は Not Applicable(スコアを捏造しない)。

## 出力フォーマット

`_workspace/02_trust_calibrator.md` に:

```markdown
# Trust Audit: <repo>
## スコア: N/10 — <一言根拠>
## verdict モデル
<binary か中間状態を持つか>
## rollout 勾配
<audit-first の有無、adoption path>
## suppression
<誤検知の局所的出口>
## FP feedback loop
<計測・分類・修正の機構>
## 信頼リスクと提案
| Severity | リスク | 位置 | 提案 |
|----------|--------|------|------|
```

## アンチパターン(減点対象)

| パターン | なぜ減点 |
|----------|----------|
| 証拠不足でも binary 断定 | 嘘 = 信頼毀損 |
| いきなり enforce(audit モード無し) | 最初の FP で見捨てられる |
| suppression が無い/全体 off のみ | 1件の FP がツール全放棄に直結 |
| FP rate を計測しない | potency が改善しない、信頼が下がり続ける |
| 判定と gate が密結合 | ユーザーが厳しさを調整できない |
