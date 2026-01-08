---
name: review-flow
description: PRをペアプロ形式でレビュー。PR作成後に実行するフローです
argument-hint: [url]
model: opus
---

PR $1 について理解しPR authorの身になってペアプロセッションを開始します。
レビュワーにわかりやすいように解説をしてください。

gh pr checkoutを実行して現在のブランチに切り替えるもしも異なるリポジトリにいる場合は ~/ghq/githtub.com/{owner}/{repo} に移動してください。

parallelに以下のsubagentsを実行します
- code-review subagent を使用してコードレビューを実行します。
- QA subagent を使用して実際のユースケースを想定したテストケースをBash Toolで再現し振る舞いレビューします。
    - 動作確認手順
    - 期待される結果
    - 実際の結果
    - もしも問題があればその詳細

以下の項目を報告してください
- コードの解説
- code-review agentのフィードバック内容/動作確認結果を元にした代理質問を提案してください
  そこからペアプロセッションを開始します。
    - 〇〇のような入力があった場合、どのような挙動になりますか？
    - この処理のパフォーマンスが気になりますが、どの程度の負荷がかかりますか？

Background Task:
現在のPR Commentのうち @coderabbitai によるコメントのうちresolveではないものを全て取得します。
    - それぞれのコメントに対してBackground parallel taskで以下を進めます。
    1. その指摘の再現可能性を動作確認を通して確認する
    2. 修正が妥当な場合、Prompt for AI Agents の内容を元に 新たなsubtaskを作成して修正する
