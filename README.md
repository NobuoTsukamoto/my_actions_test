# my_actions_test
This is a repository for me to try GitHub Actions.

## Restore cache の起動失敗の切り分け

対象: [失敗したジョブ](https://github.com/NobuoTsukamoto/meta-onnxruntime/actions/runs/41293258185/job/124828461088?pr=97)
／[元のワークフロー](https://github.com/NobuoTsukamoto/meta-onnxruntime/blob/main/.github/workflows/build_intel.yml)

ログで確認できたエラーは次のとおりです。

```text
An error occurred trying to start process '/home/runner/actions-runner/cached/2.338.2/externals/node24/bin/node'
... No such file or directory
```

Restore cache の JavaScript が起動する前の失敗です。Save cache と checkout の後処理も同じエラーになっています。キャッシュの有無や展開先の権限が原因と判断できるログではありません。Node 実体、シンボリックリンク先、ELF インタープリターなどの消失を調べます。元ログだけでは、どの操作が原因かは未確定です。

`.github/workflows/reproduce-cache-restore.yml` を GitHub に反映し、Actions の **Diagnose cache restore startup → Run workflow** で実行します。手動起動のみで、BitBake とキャッシュ保存は実行しません。

| cleanup | 実行内容 |
| --- | --- |
| none | クリーンアップなしの対照 |
| opt | `/opt/*` の削除のみ |
| toolcache | `$AGENT_TOOLSDIRECTORY` の削除のみ |
| apt | 元の apt purge / autoremove / autoclean のみ |
| original | 元のクリーンアップ一式とパッケージインストール |

元ジョブと同じ `ubuntu-22.04` と action のコミット SHA を使います。runner のバージョンやイメージは更新されるため、元ジョブの runner `2.338.2`、イメージ `20261025.340.1` と比較してください。元ログでは Node 20 用 action が Node 24 で強制実行されています。再現用ではこの設定を上書きせず、実行ログで実際のランタイムを確認します。

`Diagnose cleanup` の各操作後に `Node execution: OK / FAILED`、`namei`、`readlink`、`file`、`ldd` を出力します。初めて FAILED に変わった操作と、Restore cache の起動エラーを対応させてください。apt の削除パッケージ一覧も出力します。`none` でも失敗した場合はクリーンアップ以外の環境要因を調べます。`original` だけ失敗する場合は操作の組み合わせ、または追加の削除・インストール操作を各スナップショットから絞れます。

このリポジトリから元リポジトリのキャッシュは参照できません。同じキーでも通常は cache miss になりますが、元設定の `fail-on-cache-miss` は false のため、正常な起動なら miss 自体は失敗になりません。今回はキャッシュ転送の再現ではなく、action の起動失敗を切り分けます。

`scripts/diagnose-cache-cleanup.sh` は使い捨ての GitHub-hosted runner 専用です。各ジョブの Summary と生ログを確認してください。ローカル環境では実行せず、構文チェックのみ行います。
