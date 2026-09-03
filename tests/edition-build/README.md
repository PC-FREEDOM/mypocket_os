# Base/Standard edition分離ビルド 静的/モックテスト

`config/package-lists.d/`・`scripts/build.sh`・`scripts/update-test-iso.sh`・
`scripts/create-test-vm.sh`のedition選択機構に対する、実lb・実sudo・実virsh・
実ISOビルド・実libvirt操作を一切行わない静的/モックテストハーネス。

## 実行方法

```sh
tests/edition-build/run.sh
```

個別に実行する場合:

```sh
tests/edition-build/test_package_lists.sh
tests/edition-build/test_media_label.sh
tests/edition-build/test_build.sh
tests/edition-build/test_update_iso.sh
tests/edition-build/test_create_vm.sh
```

## 内容

- `test_package_lists.sh`: `config/package-lists.d/`の内容を静的に確認する
  (commonにStandard専用アプリが含まれないこと、standardに現在の12
  パッケージが揃っていること、`config/package-lists/`直下に恒久ファイルが
  残っていないこと)。
- `test_media_label.sh`: `auto/config`の`--iso-volume`・`--iso-application`・
  `--iso-publisher`・`--hdd-label`(ISO/USBメディア名としてOSやファイル
  マネージャーに表示される値)を静的に確認する。4設定がいずれも存在し、
  値に`Debian`を含まず`MyPocketOS`系の表記になっていること、
  `--iso-volume`の`@ISOVOLUME_TS@`展開後の文字数がISO9660の32文字制限に
  収まること、`--iso-preparer`は今回の変更対象外のため未設定のままである
  ことを検証する。`config/binary`・`config/common`・`config/chroot`・
  `config/bootstrap`は`lb config`が生成する成果物であり`.gitignore`対象の
  ためリポジトリには存在しない(誤って追跡対象に戻っていないことも確認
  する)。ローカル環境で`lb config`実行済みで`config/binary`が存在する
  場合に限り、そこに書き出された`LB_ISO_VOLUME`等の値が`auto/config`の
  設定値と一致するかも追加確認するが、CI等`config/binary`が存在しない
  環境ではこの追加確認をスキップする(既存方針どおり実`lb`は呼び出さない)。
- `test_build.sh`: `scripts/build.sh`をsandbox (mktemp -d) へコピーし、
  モック`lb`/`sudo`で引数検証・package-list一時配置内容・`--image-name`・
  cleanup (成功時/1回目`lb config`失敗時/`lb clean`失敗時/2回目
  `lb config`失敗時/`lb build`失敗時/ISO不存在時/SIGINT時)・既存ファイル
  がある場合の上書き防止を検証する。モック`lb`はconfig/common相当の
  状態ファイル (sandbox内で永続) を保持し、`lb config --image-name`で
  更新・`lb clean`実行時点の値でISOを削除するという実lbの挙動を再現する。
  これにより、`config -> clean -> config -> build`という呼び出し順序
  そのもの (単なる呼び出しの有無ではなく順序と、各呼び出し時点での
  `--image-name`/削除対象の内容) を1本の時系列ログで検証し、さらに
  Base→Standard・Standard→Base・同edition再ビルドの往復シナリオで、
  他edition ISOが一切削除されないことを検証する (実ビルドで発見された
  「前回editionのLB_IMAGE_NAMEが残った状態でlb cleanが走り、前回edition
  側のISOを誤って削除する」不具合の再現・fix確認)。
- `test_update_iso.sh`: 引数検証 (Debianホスト確認より前で完結するため
  実スクリプトを直接実行) と、モック`virsh`によるISO_SRC解決・ISO不存在
  時の停止を検証する。SHA-256照合ロジック等、今回変更していない安全機構は
  静的な存在確認に留める。
- `test_create_vm.sh`: 引数検証 (edition必須化・`--firmware`との併用・
  順序が逆でも解釈が変わらないこと) を実スクリプトの診断出力
  (`== 処理対象の絶対パス ==`ブロック) で検証する。この開発ホストには
  既存の実VM用ディスクが既に存在し、それらを操作せずに「ISO不存在なら
  virt-installへ進まない」ことを実行時に最後まで確認することはできない
  ため、この点のみ静的な構造確認 (ISO存在チェックがvirt-install呼び出しより
  前にあること) で代替する。詳細はファイル冒頭のコメント参照。

## production整合性への影響

`scripts/build.sh`・`scripts/update-test-iso.sh`・`scripts/create-test-vm.sh`
自体への書き込みは行わない (常にsandbox・一時ファイルへのコピー経由、
または実スクリプトへは引数を渡すだけで内容を変更しない)。`run.sh`は
実行前後でこの3ファイルのSHA-256を比較する。
