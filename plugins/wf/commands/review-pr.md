---
name: review-pr
description: PRをペアプロ形式でレビュー
argument-hint: [url]
model: haiku
disable-model-invocation: false
---

PR $1 について理解しPR authorの身になってペアプロセッションを開始します。
レビュワーにわかりやすいように解説をしてください。

gh pr checkoutを実行して現在のブランチに切り替えるもしも異なるリポジトリにいる場合は ~/ghq/githtub.com/{owner}/{repo} に移動してください。

parallelに以下のsubagentsを実行します
- code-reviewer subagent を使用して初期レビューを実行します。
- explorer subagent を使用してPRの変更点を整理します。
    - 追加した処理
    - 変更した処理
    - 削除した処理
    - 影響のある他コンポネント
- dynamic-test subagent を使用してPRの対象となる機能を実際にBash Toolを用いて動作確認します。
    - 動作確認手順
    - 期待される結果
    - 実際の結果
    - もしも問題があればその詳細

以下の項目を報告してください
- コードの解説
- code-reviewerのフィードバック内容/動作確認結果を元にした代理質問を提案してください
  そこからペアプロセッションを開始します。
    - 〇〇のような入力があった場合、どのような挙動になりますか？
    - この処理のパフォーマンスが気になりますが、どの程度の負荷がかかりますか？
