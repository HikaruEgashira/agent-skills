---
description: 分割commit
model: haiku
---

大きな変更を論理的な単位に分割してコミットします。LLMがgit diffを分析して意味のある最小単位を提案し、`git-sequential-stage`ツールによる自動化された逐次ステージングでコミットします。

#### git-sequential-stage

`git-sequential-stage`は、hunk単位の部分的なステージングを自動化するためのGoで実装された専用ツールです。

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

#### ワイルドカード使用の判断基準

ワイルドカード（`*`）を使用すべきケース
- ファイル内のすべての変更が意味的に一体である場合
- 新規ファイルの追加
- ファイル全体のリファクタリング（すべての変更が同じ目的）
- ドキュメントファイルの更新

hunk番号で分割すべきケース
- 異なる目的の変更が混在している場合
- バグ修正とリファクタリングが同じファイルに混在
- 機能追加と既存コードの改善が混在

⚠️ 注意点
- 「hunkを数えるのが面倒」という理由で使用するものではない。
- 意味のある最小単位でのコミットという本来の目的を必ず守ること。

## 実行手順

### Step 0: リポジトリルートに移動

```bash
# リポジトリルートを確認
REPO_ROOT=$(git rev-parse --show-toplevel)
echo "リポジトリルート: $REPO_ROOT"

# リポジトリルートに移動
cd "$REPO_ROOT"
```

### Step 1: 差分を取得

```bash
# .claude/tmpディレクトリは既に存在するため、直接ファイルを作成可能

# 新規ファイル（untracked files）をintent-to-addで追加
git ls-files --others --exclude-standard | xargs git add -N

# コンテキスト付きの差分を取得（より安定した位置特定のため）
# 新規ファイルも含めて取得される
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

例：
```bash
# LLMの分析結果
# - コミット1（fix）: 
#   - src/calculator.py: hunk 1, 3, 5（ゼロ除算エラーの修正）
#   - src/utils.py: hunk 2（関連するユーティリティ関数の修正）
# - コミット2（refactor）: 
#   - src/calculator.py: hunk 2, 4（計算ロジックの最適化）

# 最初のコミット用の設定
COMMIT_MSG="fix: ゼロ除算エラーを修正

計算処理で分母が0の場合の適切なエラーハンドリングを追加"
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

残りの変更に対して同じプロセスを繰り返し：

```bash
# 残りの差分を確認
if [ $(git diff HEAD | wc -l) -gt 0 ]; then
  echo "残りの変更を処理します..."
  # Step 1（差分取得）から再開
fi
```

### Step 5: 最終確認

```bash
# すべての変更がコミットされたか確認
if [ $(git diff HEAD | wc -l) -eq 0 ]; then
  echo "すべての変更がコミットされました"
else
  echo "警告: まだコミットされていない変更があります"
  git status
fi
```

## 例

### ファイル内の意味的分割

```
変更内容: src/calculator.py
- hunk 1: 10行目のゼロ除算チェック追加
- hunk 2: 25-30行目の計算アルゴリズム最適化
- hunk 3: 45行目の別のゼロ除算エラー修正
- hunk 4: 60-80行目の内部構造リファクタリング
- hunk 5: 95行目のゼロ除算時のログ出力追加

↓ 分割結果

コミット1: fix: ゼロ除算エラーを修正
# バグ修正のhunkのみを選択（他の変更と混在しているため番号指定）
git-sequential-stage -patch=".claude/tmp/current_changes.patch" -hunk="src/calculator.py:1,3,5"

コミット2: refactor: 計算ロジックの最適化
# リファクタリングのhunkのみを選択
git-sequential-stage -patch=".claude/tmp/current_changes.patch" -hunk="src/calculator.py:2,4"
```

### 複雑な変更パターン

```
変更内容:
- src/auth.py: 認証ロジックの修正（hunk 1,3,5）とリファクタリング（hunk 2,4）
- src/models.py: ユーザーモデルの拡張（hunk 1,2）
- tests/test_auth.py: 新規テスト（hunk 1,2,3）

↓ 分割結果

コミット1: fix: 既存認証のセキュリティ脆弱性修正
# セキュリティ修正のhunkのみを選択（他の変更と混在）
git-sequential-stage -patch=".claude/tmp/current_changes.patch" -hunk="src/auth.py:1,3,5"

コミット2: feat: JWT認証機能の実装
# 新機能実装に関連する変更を選択
git-sequential-stage -patch=".claude/tmp/current_changes.patch" \
  -hunk="src/auth.py:2,4" \
  -hunk="src/models.py:*"  # モデルの変更はすべてJWT関連のため*を使用

コミット3: test: 認証機能のテスト追加
# 新規テストファイルは意味的に一体のため*を使用
git-sequential-stage -patch=".claude/tmp/current_changes.patch" -hunk="tests/test_auth.py:*"
```

# ベストプラクティス

1. 事前確認: `git status`で現在の状態を確認
2. 適切な指定方法の選択:
   - 部分的な変更: `file.go:1,3,5` （hunk番号を指定）
   - ファイル全体: `file.go:*` （意味的に一体の場合のみ）
3. 意味的一貫性: 同じ目的の変更は同じコミットに
4. Conventional Commits: 適切なプレフィックスを使用, 1行にまとめる
   - `feat:` 新機能
   - `fix:` バグ修正
   - `refactor:` リファクタリング
   - `docs:` ドキュメント
   - `test:` テスト
   - `style:` フォーマット
   - `chore:` その他
