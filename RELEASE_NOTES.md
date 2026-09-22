# MyPocketOS Release Notes

## Initial Release

MyPocketOSは、Debian 13をベースにした軽量なデスクトップLinuxです。

USBメモリから起動して使えるLive環境と、必要に応じて内蔵ストレージへ
インストールして利用できる構成を目指しています。

## 主な特徴

- Debian 13 ベース
- Openbox + tint2 + jgmenuによる軽量デスクトップ
- 日本語表示・日本語入力対応
- IBus / Mozc対応
- CalamaresによるGUIインストール
- USB Live起動
- `/home` を中心としたPersistence対応
- Wi-Fi設定のPersistence対応
- Flatpak標準搭載
- Base版 / Standard版の2エディション
- MyPocketOS独自ブランディング
- UEFI / Legacy BIOS起動対応
- Secure Boot環境での起動確認済み

## エディション

### Base

必要最低限のデスクトップ環境を中心に構成した軽量版です。

### Standard

Base版をベースに、日常利用向けのアプリケーションや機能を追加した標準版です。

## インストール

CalamaresによるGUIインストーラーを搭載しています。

初回リリースで正式にサポートするのは、
**インストール先ディスク全体を使用する「ディスクの消去」方式**です。

通常インストールには、以下が必要です。

- インターネット接続
- 16 GiB以上のインストール先ストレージ
- 約2 GiB以上のRAM

## Persistence

USBメモリ上にPersistence領域を作成することで、
Live環境でもユーザーデータや設定を保持できます。

Persistenceは、配布するISOをUSBメモリへ書き込んだ上で、Live環境内の
GUIを使って利用者自身が作成します。あらかじめPersistence領域を組み込んだ
配布用IMGファイルは、初回リリースでは提供しません。

初回リリースでは主に以下を保持対象とします。

- `/home`
- ユーザー設定
- Wi-Fi接続設定

追加アプリについては、Persistenceとの相性を考慮し、
`flatpak --user` の利用を推奨します。

## 推奨USB容量

- 最小目安: 16GB
- 推奨: 32GB以上

## 検証状況

初回リリースに向け、以下の確認を実施しています。

- Virtual Machine上でのLive起動
- Standard版のCalamaresインストール
- Legacy BIOS実機での起動・インストール
- UEFI実機での起動・インストール
- Secure Boot有効環境での起動
- Persistence基本動作
- 日本語入力
- Wi-Fi
- サウンド
- タッチパッド
- バッテリー表示
- Openbox / tint2 / jgmenuデスクトップ

ハードウェアやファームウェアの組み合わせによっては、
追加の設定が必要になる場合があります。

## 既知の問題

既知の制約・注意事項については `KNOWN_ISSUES.md` を参照してください。

## ライセンス

MyPocketOSのプロジェクトコードはGNU General Public License Version 3
(GPLv3)のもとで公開しています。

同梱しているソフトウェアやアセットには、それぞれ個別のライセンスが適用される場合があります。
詳細は `THIRD_PARTY_NOTICES.md` を参照してください。

## ISO / SHA-256

初回リリースで公開するBase版・Standard版の最終ISOサイズおよびSHA-256は、
リリース用確定コミットから最終ビルドを行った後に記録します。
