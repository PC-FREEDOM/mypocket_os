MyPocketOSは、DebianとOpenboxをベースにした、
日本語環境を持ち歩ける軽量デスクトップLinuxです。

USBからLive起動でき、必要に応じて設定、データ、
追加アプリを永続保存できます。内蔵ストレージへの
通常インストールにも対応します。

Tailsの携帯性を参考にしていますが、
匿名化や高度な痕跡防止を目的としたOSではありません。

## ビルド手順

Debian 13 (trixie) 上で live-build を使い、ISOイメージをビルドします。

### 前提

- Debian 13 (trixie) の環境であること
- `live-build` パッケージがインストールされていること
- `sudo` でroot権限を取得できること (`lb clean` / `lb build` はroot権限が必要)

### 実行方法

```sh
./scripts/build.sh
```

`scripts/build.sh` は以下の順に実行します。

1. `sudo lb clean` — 前回のビルド生成物 (chroot・binary・各段階の生成物) を削除。パッケージキャッシュは再利用のため残す
2. `lb config` — `auto/config` (`lb config noauto ...`) を実行し、`config/` 以下の設定を生成
3. `sudo lb build` — chrootの構築とISOイメージの生成

実行ログは `build.log` に保存されます。

ビルドに成功すると、プロジェクトルート直下に `live-image-amd64.hybrid.iso` が生成されます。出力ISOおよび live-build の作業生成物 (`config/binary` などの生成済み設定、`chroot/`、`cache/`、`local/`、`.build/` 等) はGit管理対象外です。

### 今回の実装範囲

初回起動確認用の最小構成であり、以下を含みます。

- amd64 / iso-hybrid、Debian 13 trixie (archive areas: main contrib non-free-firmware)
- Openbox + tint2 + LightDM (GTK greeter) + PCManFM + LXTerminal
- NetworkManager (nm-applet) / lxpolkit (PolicyKit認証エージェント)
- 日本語ロケール (ja_JP.UTF-8) ・ 日本語キーボード (jp) ・ タイムゾーン (Asia/Tokyo)
- Noto CJKフォント / Fcitx5-Mozc
- SPICEクリップボード・画面統合
- PipeWire音声基盤
- 音量設定とトレイアイコン
- zram圧縮スワップ
- jgmenuアプリメニュー
- tint2メニューボタン
- Openbox右クリックメニューとの併用
- Conkyシステム情報表示
- Openboxキーボードショートカット
- 日本語Openbox右クリックメニュー
- 電源・セッション操作 (ログアウト・再起動・電源オフ)
- ファームウェア設定への再起動
- GUI確認ダイアログ (yad)

電源・セッション操作について:

- ログアウト・再起動・電源オフ・ファームウェア設定はすべて
  `/usr/local/bin/mypocketos-power` に集約されており、jgmenu (アプリメニュー内
  「電源・セッション」) とOpenbox右クリックメニュー (「電源・セッション」
  サブメニュー) の両方から同じ確認ダイアログ経由で呼び出されます。
- sudoは使用せず、systemd-logind (`systemctl`) とPolicyKit (`lxpolkit`) の
  組み合わせに委ねています。
- ファームウェア設定画面への再起動は、UEFIおよび機器 (ファームウェア) 側の
  対応が必要です。対応可否は `systemd-logind` の
  `CanRebootToFirmwareSetup()` (D-Bus) で都度判定し、非対応と判定された
  場合は再起動を行わず、日本語のGUIメッセージで理由を表示します。

以下は未実装です (今後の課題)。

- 永続化 (persistence)
- Calamaresによるインストーラ
- 一般アプリ一式
- 独自テーマ・ブランディング
- 外部リポジトリからテーマ等を取得するフック

### 既知の制限

- jgmenuの検索入力は英字検索のみ動作確認済みです。Fcitx5-Mozcを使用した日本語検索は
  現時点では正常に機能しません。日本語でのメニュー表示、およびカテゴリからのアプリ
  起動には影響しません。

## Live環境のログイン

MyPocketOSのLive環境は、通常起動時にlive-configの自動ログイン機能により
自動的にデスクトップへログインします（ユーザー操作は不要です）。

Openbox右クリックメニューの「電源・セッション」→「ログアウト」(またはjgmenuの
同項目) を選択すると、LightDMのログイン画面へ戻ります。ログイン画面から
再ログインする場合の既定のユーザー名・パスワードは次のとおりです。

- ユーザー名: `user`
- パスワード: `live`

これは `live-config`（`0030-live-debconfig_passwd` スクリプト、コメント
"Default password is: live"）が設定するDebian Live標準の既定値であり、
MyPocketOS独自の設定ではありません。また、将来実装予定の通常インストール環境
（Calamares等）で作成されるユーザーアカウントの認証情報とは別のものです。

VMでの動作確認により、Openbox右クリックメニューの「ログアウト」を実行して
LightDMのログイン画面へ正常に戻ること、および上記の既定値（`user` / `live`）で
LightDMから再ログインできることを確認済みです。再ログイン後は以下も確認済みです。

- `whoami` が `user` を返す
- `hostname` が `mypocketos` を返す
- Openboxが1プロセスのみ起動している（多重起動なし）
- Conkyが1プロセスのみ起動している（`-U`オプションによる多重起動防止が機能）
- tint2・PCManFM・Conkyが正常に再表示される

## Live環境の再起動

Live環境の起動パラメータ (`auto/config` の `--bootappend-live`) に
`noeject` を指定しています。これは、Live環境の再起動時にメディアの取り外し
待ちにならないようにするためのものです。Liveメディアを接続したまま
再起動できるようにする設定であり、通常インストール環境の再起動には
影響しません (live-boot(7) 参照)。

今回のテスト結果は次のとおりです。

- 「電源・セッション」→「再起動」(`mypocketos-power`) から `systemctl reboot`
  が実行され、`noeject` によりメディアの取り外し待ちが表示されないことを
  確認しました。
- 永続VM `mypocketos-test` で、同じISOを接続したままLive環境へ再起動できる
  ことを確認しました。
- 再起動後、`hostname` が `mypocketos` を返すこと、稼働時間がリセットされて
  いること、`/proc/cmdline` 内に `noeject` が1件だけ含まれていることを
  確認しました。

## QEMU/KVM検証環境

`scripts/create-test-vm.sh` と `scripts/update-test-iso.sh` は、
**MyPocketOSのISO内ではなく、開発ホスト (Debianで virt-install/virsh/QEMU/KVM
がセットアップ済みの環境) で実行するスクリプト**です。ビルドしたISOを
QEMU/KVM上のVMで手軽に確認するためのものであり、MyPocketOS自体には含まれません。

前提として、`qemu:///system` が使えること (libvirtの `default` ネットワークが
active であること)、および `sudo` が使えることが必要です。

### 初回作成

```sh
./scripts/build.sh                 # ISOをビルド (未実施の場合)
./scripts/create-test-vm.sh
```

`live-image-amd64.hybrid.iso` を `/var/lib/libvirt/images/MyPocketOS-dev.iso`
へコピーし (コピー後にSHA-256を照合)、`mypocketos-test` という名前の永続VMを
`qemu:///system` に作成して起動します。VMはこのISOから直接Live起動します
(`--import` によりインストーラは起動しません)。

VMには16GiBのqcow2仮想ディスクも接続されますが、**これは将来のインストーラ
検証用であり、現時点のLive起動には使用しません**(起動順序はCD-ROMが先、
仮想ディスクが後です)。

### ISO再ビルド後の更新手順

```sh
virsh --connect qemu:///system shutdown mypocketos-test   # VMを停止
./scripts/build.sh                                        # ISOを再ビルド
./scripts/update-test-iso.sh                               # ISOのみを更新
virsh --connect qemu:///system start mypocketos-test       # VMを起動
```

`update-test-iso.sh` は、`mypocketos-test` が存在しない場合や、状態が厳密に
「停止 (shut off)」でない場合 (実行中・一時停止中・状態取得失敗などを含む)は
何もせず失敗します。VM定義や仮想ディスクには一切触れず、ISOファイルのみを
更新します。

### 動作確認

実機でのテストにより、次を確認済みです。

- `create-test-vm.sh` で永続VM `mypocketos-test` を作成できたこと
- CD-ROMが `boot.order=1`、仮想ディスクが `boot.order=2` であること
- SPICE・クリップボード共有・spice-vdagentが動作すること
- VM実行中に `update-test-iso.sh` を実行するとISO交換が拒否されること
- VM停止後は、ISOの更新とSHA-256の一致確認に成功すること
- 更新後、同じVMからMyPocketOSをLive起動できること

### virt-managerで開く

virt-managerを起動し、`QEMU/KVM` (qemu:///system) の接続の下に
`mypocketos-test` が表示されます。ダブルクリックするとSPICE経由で画面に
接続できます (`listen=127.0.0.1` のためホスト上でのみ接続可能です)。

### VMの削除について

これらのスクリプトは、VM・仮想ディスク・ISOを削除する機能を意図的に
実装していません。不要になった場合は、virt-managerで対象のVM名が
`mypocketos-test` であることを確認したうえで、手動で管理してください
(誤削除防止のため、本READMEでは削除コマンドは案内しません)。

## Live永続化基盤

- 起動メニューは、通常Liveと永続Liveで分かれています
  (BIOS/Syslinux: `MyPocketOS Live` / `MyPocketOS Live (Persistence)` /
  `MyPocketOS Live (Fail-safe)` の3ラベル。UEFI/GRUB も同名の3項目)。
- 通常Liveには `nopersistence`、永続Liveには `persistence` の起動
  パラメータが付きます。
- 現段階で永続化の対象となるのは `/home` のみです。
- 永続化には、ext4でフォーマットしラベルを `persistence` にした
  パーティションと、そのルートに置く `persistence.conf` (中身は
  `/home` の1行だけ) が必要です。
- 暗号化 (LUKS等) は未実装です。
- GUIによるパーティション作成は未実装です。
- `/home` 配下の一般アプリ設定・ユーザーデータは保存対象です。
- 追加インストールしたアプリ本体、パッケージ一覧、APTキャッシュの永続化は
  未実装です。

### `/` unionを採用しない理由

- `/` unionはシステム全体の変更を保存する方式であり、カーネルやLive基盤を
  ISO更新によって提供するという方針と衝突します。
- 今回はユーザーデータとホームディレクトリ配下の設定だけを永続化の対象と
  します。
- 一般アプリの永続化は、将来的にパッケージ一覧とAPTキャッシュを使う
  別機能として実装する予定です。

### 手動テスト手順 (開発用VM専用)

**警告**

- この手順は開発用VM `mypocketos-test` 専用です。
- 対象デバイス (`/dev/vda`) の内容はすべて失われます。
- 実機やUSBメモリでは実行しないでください。
- デバイスが `/dev/vda` であることを確認できない場合は中止してください。
- 実際のデバイス名は環境により異なるため、この手順の `/dev/vda` は
  製品利用者向けの一般化された手順ではありません。

手順:

1. VM `mypocketos-test` 上のLive環境で、`lsblk` を実行し、`/dev/vda` が
   16GiBの空ディスク (CD-ROMではない) であることを確認する。

   ```sh
   lsblk
   ```

2. `parted` でGPTと、ext4用のパーティション `/dev/vda1` を作成し、
   カーネルにパーティション情報を再読込させてから、`/dev/vda1` が
   実際に存在することを確認する。**ここで `/dev/vda1` の存在を
   確認できない場合は、以降の手順に進まず中止する。**

   ```sh
   sudo parted -s /dev/vda -- mklabel gpt
   sudo parted -s /dev/vda -- mkpart persistence ext4 1MiB 100%
   sudo partprobe /dev/vda
   sudo udevadm settle
   lsblk -f /dev/vda
   ```

3. `/dev/vda1` をext4でフォーマットし、ラベルを `persistence` にする。

   ```sh
   sudo mkfs.ext4 -L persistence /dev/vda1
   ```

4. 一時的にマウントする。

   ```sh
   sudo mkdir -p /mnt/persistence
   sudo mount /dev/vda1 /mnt/persistence
   ```

5. `persistence.conf` を作成する (中身は `/home` の1行のみ)。シェルの
   リダイレクトでは書き込み権限の問題が起きうるため、`tee` を使う。
   作成後は内容を確認する。

   ```sh
   printf '/home\n' | sudo tee /mnt/persistence/persistence.conf >/dev/null
   cat /mnt/persistence/persistence.conf
   ```

6. 同期してアンマウントする。

   ```sh
   sync
   sudo umount /mnt/persistence
   ```

7. VMを再起動し、ブートメニューから「MyPocketOS Live (Persistence)」を
   選択する。

8. 永続Liveで起動した直後、テストファイルを作成する前に、永続化が
   実際に有効になっていることを確認する。`/home` がラベル `persistence`
   の `/dev/vda1` から提供されていることを確認できてから次に進む。

   ```sh
   findmnt --target /home
   lsblk -f
   ```

9. `/home/user` にテストファイルを作成する (例: `touch ~/persistence-test`)。

10. 永続Liveで再起動し、テストファイルが残っていることを確認する。

11. 通常Live (`MyPocketOS Live`) で起動し、同じファイルが見えないことを
    確認する。

12. 再び永続Liveで起動し、テストファイルが見えることを確認する。

### 動作確認

以下は、開発用QEMU/KVM VM `mypocketos-test` 上で、BIOS/Syslinux起動により
実際に確認した内容です。検証環境は、16GiBの空の `/dev/vda` に対して
`/dev/vda1` をext4で作成し、ファイルシステムラベルを `persistence`、
`persistence.conf` の内容を `/home` の1行としたものです。

1. BIOS/Syslinuxの起動メニューに、次の3項目が表示されることを確認しました。
   - `MyPocketOS Live`
   - `MyPocketOS Live (Persistence)`
   - `MyPocketOS Live (Fail-safe)`

2. 通常Live (`MyPocketOS Live`) では次を確認しました。
   - カーネルコマンドラインに `nopersistence` が1件、`persistence` が
     0件であること
   - `/home` がLive環境のoverlayであること
   - `/dev/vda1` がマウントされないこと
   - 永続領域内に作成したテストファイルが表示されないこと

3. Persistenceモード (`MyPocketOS Live (Persistence)`) では次を確認しました。
   - カーネルコマンドラインに `persistence` が1件、`nopersistence` が
     0件であること
   - `/home` が `/dev/vda1[/home]` としてマウントされていること
   - `/home/user` が `user:user` 所有、パーミッション `0700` で
     作成されていること

4. `/home/user/persistence-test` を作成し、Persistenceモードで再起動した
   後も、内容と所有者が維持されていることを確認しました。

5. 通常Liveへ切り替えるとテストファイルは表示されず、再びPersistenceモード
   へ戻ると同じ内容で再表示されることを確認しました。

6. 各再起動でカーネルの `boot_id` が変化していることを確認しており、
   同一セッション内の見かけ上の確認ではないことを確認しています。

**未確認事項**

- UEFI/GRUB設定 (`config/bootloaders/grub-pc/grub.cfg`) は、生成された
  設定ファイルの静的検証 (`grub-script-check` 等) には合格していますが、
  UEFI VMでの実際の起動メニュー表示およびPersistence起動そのものは
  今回未確認です。
- GUIによる永続領域作成は未実装です。
- LUKSによる暗号化は未実装です。
- 追加インストールしたアプリ本体、パッケージ一覧、APTキャッシュの
  永続化は未実装です。

上記のとおり、「動作確認済み」の範囲はBIOS/Syslinuxおよび `/home` の
永続化に限定されます。UEFI/GRUBや、GUI作成・暗号化・アプリ本体の永続化
といった未実装機能については、確認済みとはみなしていません。
