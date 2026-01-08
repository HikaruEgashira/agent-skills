---
name: commit-action
description: 変更を意味ある単位に分割コミット。逐次実行するのではなくPRを作成する時に呼び出す
model: haiku
---

`git-sequential-stage`hunk単位の部分的なステージングを実行するためのツールです。
`git-sequential-stage`を用いて大きな変更を論理的な単位に分割してコミットします。

```bash
# hunk番号を指定して部分的にステージング
git-sequential-stage -patch="path/to/changes.patch" -hunk="src/main.go:1,3,5"

# ファイル全体をステージング（ワイルドカード使用）
git-sequential-stage -patch="path/to/changes.patch" -hunk="src/logger.go:*"

# 複数ファイルの場合（ワイルドカードと番号指定の混在も可能）
git-sequential-stage -patch="path/to/changes.patch" \
  -hunk="src/main.go:1,3" \
  -hunk="src/utils.go:*" \
  -hunk="docs/README.md:*"
```

## 実行手順

### Step 0: リポジトリルートに移動
### Step 1: 差分を取得

```bash
git ls-files --others --exclude-standard | xargs git add -N

# より安定した位置特定のため
git diff HEAD > .claude/tmp/current_changes.patch
```

### Step 2: LLM分析

LLMがhunk単位で変更を分析し、最初のコミットに含めるhunkを決定：

- hunkの内容を読み取る: 各hunkが何を変更しているか理解
- 意味的グループ化: 同じ目的の変更（バグ修正、リファクタリング等）をグループ化
- コミット計画: どのhunkをどのコミットに含めるか決定

必要に応じて、hunk数を確認：
```bash
# 全体のhunk数
grep -c "^@@" .claude/tmp/current_changes.patch

# 各ファイルのhunk数
git diff HEAD --name-only | xargs -I {} sh -c 'printf "%s: " "{}"; git diff HEAD {} | grep -c "^@@"'
```

### Step 3: 自動ステージング

選択したhunkを`git-sequential-stage`で自動的にステージング：

```bash
# git-sequential-stageを実行（内部で逐次ステージングを安全に処理）
# 部分的な変更をステージング（hunk番号指定）
git-sequential-stage -patch=".claude/tmp/current_changes.patch" -hunk="src/calculator.py:1,3,5"

# ファイル全体をステージング（意味的に一体の変更の場合）
git-sequential-stage -patch=".claude/tmp/current_changes.patch" -hunk="tests/test_calculator.py:*"

# 複数ファイルの場合（混在使用）
git-sequential-stage -patch=".claude/tmp/current_changes.patch" \
  -hunk="src/calculator.py:1,3,5" \
  -hunk="src/utils.py:2" \
  -hunk="docs/CHANGELOG.md:*"

# コミット実行
git commit -m "$COMMIT_MSG"
```

### Step 4: 繰り返し
### Step 5: 最終確認

#### ワイルドカード使用の判断基準

ワイルドカード（`*`）を使用すべきケース
- ファイル内のすべての変更が意味的に一体である場合
- 新規ファイルの追加
- ファイル全体のリファクタリング（すべての変更が同じ目的）
- ドキュメントファイルの更新
- 「hunkを数えるのが面倒」という理由で使用するものではない。

# ベストプラクティス

- 意味的一貫性: 同じ目的の変更は同じコミットに
- Conventional Commits: 適切なプレフィックスを使用, 1行にまとめる
   - `feat:` 新機能
   - `fix:` バグ修正
   - `refactor:` リファクタリング
   - `docs:` ドキュメント
   - `test:` テスト
   - `style:` フォーマット
   - `chore:` その他
