# harness — Agent Team & Skill Architect

> ドメインを渡すと、専門 agent チームと彼らが使う skill を生成する**メタスキル**。"who"(agent)と "how"(skill)を分離して設計する。

ある作業を自動化したいとき、ふつうは1つのプロンプトに役割も手順も詰め込む。harness はそれを2層に割る:

```
agent (who)   .claude/agents/{name}.md     役割・原則・通信プロトコル
skill (how)   .claude/skills/{name}/SKILL.md  手順・知識・スクリプト
orchestrator  .claude/skills/{orch}/SKILL.md  誰が・いつ・どの順で協調するか
```

分離する理由は3つ:agent 定義はファイルなので次セッションでも再利用できる、明示的な通信プロトコルが協調品質を保証する、そして同じ skill を複数 agent で共有できる。**agent team がデフォルトの実行モード**で、2つ以上の agent が協調するなら必ずチームを第一候補に評価する。

## 何をするか

harness skill が発火すると、Phase 0 でまず既存の `.claude/agents/` `.claude/skills/` `CLAUDE.md` を読んで現状を確定し、新規ビルド / 既存拡張 / 運用保守 のどれかに分岐する。

| Phase | 内容 |
|-------|------|
| 0. Status Audit | 既存資産を読み、ドリフトを検出し、実行計画を確認 |
| 1. Domain Analysis | ドメイン・タスク種別・技術スタック・ユーザー習熟度を分析 |
| 2. Team Architecture | 実行モード(team / subagent / hybrid)とパターン(pipeline / fan-out / expert pool / producer-reviewer / supervisor / hierarchical)を選択 |
| 3. Generate Agents | 各 agent を `.claude/agents/{name}.md` に定義(built-in type でも定義ファイル必須、全 agent `model: opus`) |
| 4. Generate Skills | 各 skill を生成。description は assertive に、SKILL.md body は 500 行未満、progressive disclosure |
| 5. Orchestration | team/sub/hybrid のオーケストレーター skill を生成し、データ受け渡しとエラー処理を規定、CLAUDE.md に pointer 登録 |
| 6. Validation | 構造・モード別・trigger・dry-run を検証し、test scenario を書く |
| 7. Evolution | 実行後にフィードバックを集め、出力品質→skill / 役割→agent / 順序→orchestrator へ振り分けて反映 |

harness は作って終わりの成果物ではなく、フィードバックで進化し続けるシステムとして扱う。

## 使い方

### インストール

```bash
claude plugin marketplace add HikaruEgashira/agent-skills
claude plugin install harness
```

### 起動

```
cd <harness を組みたい project>
# 「この project の harness を組んで」
# 「このドメインの agent team を設計して」
# 「既存の harness を監査して sync して」
```

harness skill が発火し、対話しながら `.claude/agents/` と `.claude/skills/` を生成し、`CLAUDE.md` に orchestrator の trigger pointer を登録する。生成された harness は、別タスクの中で orchestrator skill が自律的に発火して動く。

## 設計原則

- **agent team が最優先デフォルト** — 2+ agent の協調は `TeamCreate` + `SendMessage` + `TaskCreate` で自己協調させる。result handoff だけで足りるときのみ subagent を選ぶ。
- **定義ファイル必須** — Agent ツールの prompt に役割を直書きするのは禁止。who と how の分離が harness の核心価値。
- **CLAUDE.md には pointer だけ** — agent/skill リスト・ディレクトリ構造・change log は載せない。毎セッション読まれるので trigger rule のみ。change log はこの README に置く(Phase 7-3)。
- **skill は lean に** — SKILL.md body は 500 行未満。詳細は `references/` へ逃がし、必要時のみロードする progressive disclosure。

## References

skill body から必要時にロードされる参照ドキュメント:

| ファイル | 内容 |
|----------|------|
| `references/agent-design-patterns.md` | 実行モード比較・チームパターン・agent 分離基準・定義テンプレート |
| `references/team-examples.md` | 実在 harness の完全なファイル例 |
| `references/orchestrator-template.md` | オーケストレーターのテンプレート・エラー処理・context-check |
| `references/skill-writing-guide.md` | skill 著述ガイド・パターン・data-schema 標準 |
| `references/skill-testing-guide.md` | テスト・評価・反復の方法論 |
| `references/qa-agent-guide.md` | QA agent の組み込み(7件の実バグ事例ベース) |

## Change log

| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-05-24 | initial build(plugin manifest 化) | all | meta-skill を配布可能な plugin として切り出し |
| 2026-05-24 | change log を CLAUDE.md から README へ移設 | SKILL.md Phase 5-4 / 7-3 | CLAUDE.md は毎セッション読まれるため history noise を排除 |
