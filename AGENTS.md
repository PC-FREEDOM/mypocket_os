# AGENTS.md

MyPocketOSリポジトリを扱うAIコーディングエージェント向けの開発ルール。
特定のAIツールに依存しない、汎用的な指示として維持する。

## 1. MyPocketOSとAI中心開発の目的

MyPocketOSは、DebianとOpenboxをベースにした軽量ポータブルLinuxである
(製品としての詳細は `mypocketos-specification-2026-08-31.md` を参照)。

このプロジェクトは、チャット履歴を持たないAIエージェントが新しいセッションで
リポジトリを開いた場合でも、開発方針・安全ルール・確認手順を自力で理解し、
人間の開発者と同等の慎重さで作業を継続できることを目指している。
本ファイルはそのための単一のエントリポイントである。会話の文脈やチャット履歴に
依存した暗黙の了解は存在しない前提で行動すること。

## 2. 情報源の役割と参照方法

このリポジトリには役割の異なる複数の情報源がある。**単純な優先順位ではなく、
それぞれが担当する領域についての「正」である。**

| 情報源 | 何についての正か |
|---|---|
| `mypocketos-specification-2026-08-31.md` | 製品として何を目指すか、意図された仕様(製品概要・設計原則・edition定義・完了条件・ロードマップ) |
| `main` ブランチ上の production code | 現在実際にどう実装されているか(意図と実装が食い違うことはあり得る) |
| `README.md` | 詳細な実装経緯・運用手順(ビルド手順、QEMU検証環境構築等)・過去の検証記録 |
| `tests/*/README.md` | 各テストスイートの設計方針・モックの考え方 |

参照する際は、知りたいことの性質に応じて適切な情報源を選ぶこと(「意図」を知りたいなら
仕様書、「今どう動くか」を知りたいならコード自身を読む、「なぜこの実装になったか」を
知りたいならREADMEの該当箇所、というように使い分ける)。

**これらの情報源の間で矛盾を発見した場合、AIが独断でどちらかを正として解決したり、
無断で一方を書き換えたりしてはならない。** 矛盾の内容を具体的に(該当ファイル・行・
食い違いの内容を明示して)ユーザーへ報告すること。そのうえで:

- 今回の作業結果・製品挙動・安全性に影響する矛盾は、報告した後に**ユーザーの
  判断を仰いでから**作業を継続する。
- 今回の作業に影響せず、安全に作業を継続できる矛盾は、記録・報告したうえで
  作業を継続してよい。

## 3. 小さな変更を優先し、無関係な変更を行わない

依頼された作業の範囲に厳密に留めること。ついでの整理・リファクタリング・
コメント修正・無関係なファイルへの変更は行わない。修正が必要な箇所を見つけても
依頼の範囲外であれば、その場で直さず、別件の候補として報告するに留める。

一つの変更は一つの目的に対応させ、feature branch・PRも機能単位で分離する
(このリポジトリの過去のPRは、Persistence機能・仕様書統合・ウィンドウスナップ機能
のようにそれぞれ独立した粒度で作られている)。

## 4. Git運用: feature branchを使用する

`main` へ直接コミットしない(GitHub側のbranch protectionでも直接pushは
拒否される)。`main` にはbranch protectionが設定されており、現在の必須
status checksは必要に応じてGitHub側(リポジトリ設定またはPR画面)で確認する
こと。CI構成は今後変更され得るため、本ファイルには具体的なcheck名を固定的
に記載しない。作業は必ずfeature branchで行う。

- ブランチ命名は用途を表す接頭辞を使う。このリポジトリで実際に使われてきた例:
  `feat/`(機能追加)、`docs/`(ドキュメント)、`test/`(テスト)、`ci/`(CI)、`build/`(ビルド関連)
- commit messageは種別を表す接頭辞をつける(例: `feat: ...`、`docs: ...`、`fix: ...`)
- 作業前に必ず `main` の状態(HEAD commit・`git status -sb` がクリーンであること)を
  確認してからbranchを作成する
- PRがmergeされたら、featureブランチはローカル・remote両方から削除する

## 5. Git操作の承認ルール

featureブランチ上での通常の開発作業、すなわち

- `git add`
- `git commit`
- featureブランチへの `git push`
- PRの作成 (`gh pr create`)

は、ユーザーから明示的に禁止・制限されていない限り、一連の開発作業として
実行してよい。

一方、以下は必ずユーザーの明示的な承認を必要とする:

- `main` へのmerge(`gh pr merge` 等)
- force push
- history rewrite(`git rebase`・`git filter-branch`・push済みcommitへの
  `git commit --amend` 等)
- ブランチの削除
- tag/releaseの作成
- その他の破壊的Git操作(`git reset --hard`・`git clean` 等、作業内容を
  失いうる操作)

ユーザーが「commitしないで」「PRはまだ作らないで」のように個別に指定した
場合は、その指示を上記デフォルトの可否より常に優先する。

## 6. sudo/root権限を前提にしないこと

AIエージェントの実行セッションには、パスワード無しの`sudo`権限が**ない**ことを
前提とする。以下は実行できないものとして扱う:

- `sudo lb build` / `sudo lb clean` を内部で呼ぶ `scripts/build.sh`
- `sudo` を要する `scripts/update-test-iso.sh` / `scripts/create-test-vm.sh`
- 実デバイスへの `mount`・`parted`・`mkfs` 等、Persistence helperが行う破壊的操作そのもの

これらを実行しようとして失敗するのではなく、実行前にこの制約を認識し、
該当する検証工程はユーザーに依頼すること(7節参照)。

## 7. 役割分担: AIと人間

このリポジトリでの基本的な役割分担は次のとおりである:

- **AI側**: featureブランチ上でのコード実装、モックテスト(非破壊、実sudo・
  実mount・実VM不使用)、静的検査、調査、および5節で許可された範囲の通常
  Git操作(add・commit・featureブランチへのpush・PR作成)までを担当する
- **人間側**: `scripts/build.sh` によるISOビルド、`scripts/create-test-vm.sh`
  によるVM作成・起動、実USBへの書き込み、実機起動、VM/実機上でのGUI目視
  確認といった実機/VM検証、重要な製品判断、および `main` への最終merge判断
  を担当する

AIエージェントは、実機/VM検証や重要な製品判断が必要な場面では、実行しようと
する前にその旨を明示し、具体的な手順(実行するコマンド、確認してほしい項目)
を提示して人間に依頼すること。

## 8. 実施していない検証をPASSとして扱わないこと

モックテストの通過・静的検査の通過と、実際のISOビルド・VM起動・実機での動作確認は
**別物**である。実施していない検証について、あたかも確認済みであるかのように
「PASS」「動作確認済み」と報告してはならない。報告する際は、何を実際に実行し、
何を実行していない(あるいは実行できない)かを明確に分けて書くこと(11節も参照)。

## 9. PR前に確認すべき4テストスイート

コードに変更を加えた場合、変更内容に関連するか否かに関わらず、PRを作成する前に
以下の4つを実行し、結果(件数・PASS/FAIL)を報告すること。一部はCIに未統合のため
(現状 `persistence-mock-tests` workflowで自動実行されるのは
`tests/persistence/run.sh` と `tests/usb-persistence-image/run.sh` のみ)、
手動での実行確認が特に重要である。

```bash
sh tests/persistence/run.sh
sh tests/edition-build/run.sh
sh tests/desktop-polish/run.sh
sh tests/usb-persistence-image/run.sh
```

## 10. `git diff --check` 等の静的確認

コミット前に、変更内容に応じて以下も確認する:

- `git diff --check`(意図しない空白文字混入の検出)
- 変更した `#!/bin/sh` ファイルの `sh -n` / `dash -n`
- 変更した `#!/usr/bin/env bash` ファイルの `bash -n`
- 変更したXMLファイルの `xmllint --noout`(または同等のwell-formedness確認)
- 実行ビットが必要なスクリプトの権限(`chmod +x`)
- モックテストを実行した際、production ファイル(GUI/helper/ビルドスクリプト
  等)がテスト実行によって意図せず変更されていないことをSHA-256等で確認する
  (`tests/persistence/run.sh` 等、既存のテストスイート自体がこの確認を
  組み込んでいる場合は、その結果を報告すればよい)

## 11. mock testとVM/実機検証を明確に区別して報告すること

報告文の中で、次の2種類を混同・混在させず、見出しや文で明確に分けること:

- モックテスト・静的検査の結果(AIが実際に実行し確認済み)
- VM/実機での目視確認・実機E2E(人間が実行した結果、またはまだ未実施であること)

「テストは全てPASSしましたが、VM上での実際の動作はまだ確認していません」のように、
確認済みの範囲と未確認の範囲を常に区別して伝える。

## 12. 仕様変更時の仕様書・README・テスト文書更新確認

コードの挙動や仕様が変わる変更を行った場合、以下が更新対象になっていないかを
都度確認し、必要であれば(ユーザーの承認を得たうえで)更新する:

- `mypocketos-specification-2026-08-31.md`(該当節)
- `README.md`(該当節)
- `tests/*/README.md`(テスト方針自体が変わる場合)

更新が必要かどうかの判断がつかない場合は、判断をユーザーに委ねて報告すること。

## 13. Persistence関連は高リスク領域として扱うこと

以下に該当するコードは、実デバイスのパーティションテーブル操作・データ消失
リスクを伴う高リスク領域として、通常よりも慎重に扱うこと。変更前に既存の
安全設計(TOCTOU対策の再検証、fail-closed方針、自動ロールバックを行わない方針等)
を理解し、それを弱める変更を行わない。

- `config/includes.chroot/usr/local/bin/mypocketos-persistence-setup`(GUI)
- `config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper`(特権helper)
- `scripts/build-usb-persistence-image.sh`
- `tests/persistence/` および `tests/usb-persistence-image/` 配下一式

これらを変更する場合は、9節の4テストスイートに加えて `git diff --check` と
static checksを必ず実行すること。

## 14. `persistence.conf` 生成箇所を変更する場合、他の生成経路への影響も確認すること

`persistence.conf` は現在、独立した複数の箇所で生成・検証されている。1箇所だけを
直して他を放置すると、経路によって異なる内容のファイルが作られる不整合が生じる。
変更時は少なくとも以下をすべて確認すること:

- `mypocketos-persistence-setup-helper` の `finalize_persistence_filesystem`
  内の書込み・サイズ検証・内容検証(Mode A・Mode B共通)
- `scripts/build-usb-persistence-image.sh` の同等ロジック(debugfsベース、
  オフラインでのIMG事前生成用)
- 上記それぞれに対応する `tests/persistence/` および `tests/usb-persistence-image/`
  内のモック・アサーション

## 15. 作業終了時の定型報告項目

作業の区切り(実装完了時、PR作成前後、merge後等)には、該当する範囲で以下を
日本語でまとめて報告する:

- 今回の変更内容の要約
- 変更したファイル一覧
- 実行した検証(9節の4テストスイート・10節の静的確認)とその結果(件数・PASS/FAIL)
- 現在のGitブランチ・`git status -sb` の内容
- commit・push・PRの状態(未実施であれば明示する)
- まだ実施していない検証・確認事項(8節・11節に基づき、VM/実機検証等)

## 16. 日本語でユーザーへ説明すること

ユーザーとのやり取り(進捗報告、確認事項の提示、調査結果の説明等)は日本語で
行う。コード中のコメント・commit message・PR本文についても、このリポジトリの
既存の慣習(日本語コメント、英語のconventional commit接頭辞 + 日本語の説明文)
に従う。
