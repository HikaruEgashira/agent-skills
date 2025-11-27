---
description: watch pr
argument-hint: [url]
model: haiku
---

PR $1 がマージ可能になるまで監視し続けます。

gh pr checkoutを実行して現在のブランチに切り替えるもしも異なるリポジトリにいる場合は ~/ghq/githtub.com/{owner}/{repo} に移動してください。

code-reviewer subagent を使用して1次レビューを実行します。
CIが通過しているかどうか確認します。

以下の場合はマージ可能ではないため1分後に再度確認します
- CIが失敗している
- まだバグが残っている
- 変更がPR Descriptionで達成したいこと満たしていない
- Bash(sleep 60)で1分待機し、再度PRの状態を確認します
- マージ可能になるまでこの操作を繰り返します

マージ可能な場合以下を報告してください。
- コードの解説
- code-reviewerのフィードバック概要
