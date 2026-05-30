# meta — Meta-Engineering Skills

> 実装する前に考えるための再利用可能なフレームワーク群と、agent team を生成・運用する2つのメタスキル harness。

`meta` は「コードを書く前/採用される前」に効く思考の足場をまとめた plugin。3つの thinking framework と、2つの harness(agent team を生み出す factory と、dev tool の PMF を採点する audit)を1つに統合している。

## 構成

| skill | 種別 | 何をするか |
|-------|------|-----------|
| `assesment` | thinking framework | 設計・計画段階のリスクアセスメント。浅い解決策を避け、根本原因を特定する |
| `incident` | thinking framework | インシデントの初動〜復旧〜事後分析を体系化し、再発防止を強化する |
| `gap-analysis` | thinking framework | 技術選定・競合分析でギャップを洗い出し、「なぜ生じたか」を自問して戦略化する |
| `harness` | meta-skill factory | ドメインを渡すと専門 agent チームと彼らが使う skill を生成する(who/how 分離) |
| `pmf-audit` | audit harness (orchestrator) | dev tool / OSS を TTFV・trust・wedge の3次元で並行監査し、合成 PMF readiness スコアを出す |
| `ttfv-audit` / `trust-audit` / `wedge-audit` | audit method | pmf-audit の各 agent が使う次元別監査メソドロジ |

`agents/` に `ttfv-auditor` / `trust-calibrator` / `wedge-scoper`(全て `model: opus`)を定義。`pmf-audit` がこの3 agent をチームで起動する。

## harness — Agent Team & Skill Architect

ある作業を自動化したいとき、ふつうは1つのプロンプトに役割も手順も詰め込む。harness はそれを2層に割る:

```
agent (who)   .claude/agents/{name}.md       役割・原則・通信プロトコル
skill (how)   .claude/skills/{name}/SKILL.md  手順・知識・スクリプト
orchestrator  .claude/skills/{orch}/SKILL.md  誰が・いつ・どの順で協調するか
```

分離理由は3つ:agent 定義はファイルなので次セッションでも再利用できる、明示的な通信プロトコルが協調品質を保証する、同じ skill を複数 agent で共有できる。**agent team がデフォルトの実行モード**。

skill body から必要時にロードされる参照は `skills/harness/references/`(agent-design-patterns / team-examples / orchestrator-template / skill-writing-guide / skill-testing-guide / qa-agent-guide)。

## pmf — PMF Engineering Audit Harness

PMF はエンジニアリングで測れる。dev tool の採用は測れる3量の積に分解できる:

```
PMF readiness ≈ TTFV を超えて到達する確率
                × 価値を信用し続ける確率
                × 価値が自分ごとになる鋭さ
```

積なので、どれか1つが 0 に近いと他が満点でも採用は起きない。`pmf-audit` が3次元を独立に採点し、最弱の次元を最優先で潰す。doctrine は3つの実 OSS から抽出した: gh-verify(resolve_repo の推測 ladder、`--audit` rollout、`--exclude` suppression)、libverify(`Indeterminate` verdict、engine としての深さ)、parsentry(`| claude -p` で価値を借りる、`npx skills add` で install を消す)。

## 使い方

```bash
claude plugin marketplace add HikaruEgashira/agent-skills
claude plugin install meta
```

各 skill は trigger で自律発火する(`assesment`/`incident`/`gap-analysis` は設計・障害・技術選定の文脈、`harness` は「harness を組んで」、`pmf-audit` は「この OSS を PMF 観点で監査して」)。

## Change log

| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-05-24 | harness initial build(plugin manifest 化) | harness | meta-skill を配布可能な plugin として切り出し |
| 2026-05-24 | change log を CLAUDE.md から README へ移設 | harness SKILL.md Phase 5-4 / 7-3 | CLAUDE.md は毎セッション読まれるため history noise を排除 |
| 2026-05-24 | pmf initial build | pmf all | PMF エンジニアリング doctrine を実行可能な agent team に結晶化 |
| 2026-05-24 | 重みの数値化 + 合成式明示 | pmf-audit | E2E 検証: 高/中 ラベルのみで合成スコアが監査者裁量でブレた |
| 2026-05-24 | 次元の責任境界を明記 | pmf-audit | E2E 検証: scope→FP が Trust/Wedge で二重計上され得る |
| 2026-05-24 | 循環検証の警告を追加 | pmf-audit | E2E 検証: example repo を採点対象にすると「模範解答付き試験」になる |
| 2026-05-24 | TTFV 8/9/10 の tiebreak 細分化 | ttfv-audit | E2E 検証: 「2つ以上」が 8 と 9 を分けられず採点者裁量に |
| 2026-05-30 | harness + pmf を meta に統合(plugin consolidation) | all | 3つの独立 plugin だった meta/harness/pmf を1つの meta-engineering plugin に畳む。install を1つに、思考フレームワークと harness を同じ傘に |
