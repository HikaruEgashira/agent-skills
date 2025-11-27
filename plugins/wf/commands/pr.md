---
description: create pr
model: haiku
---

parallelで以下を進めます。
- create create pr subtask
    - create branch and pr
    - following pr template
    - description in japanese
    提出後は gh pr checks --watch で CI 成功を確認し、必要に応じて gh pr view --web で差分を共有します。
- comment-cleaner subagent diffに含まれる不要なコメントを削除します
- code-reviewer subagent を使用してレビューを進めてその結果を出力します
