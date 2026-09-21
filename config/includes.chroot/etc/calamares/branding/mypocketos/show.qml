/* MyPocketOS - Calamares インストール中スライドショー (1枚のみ)
 *
 * Calamares 3.3.14 の slideshowAPI 2 (import calamares.slideshow 1.0) の
 * Presentation / Slide を使う (Calamares標準のスライドショーと同じ構成)。
 * branding配下に lang/ を持たないため qsTr() は原文をそのまま表示する。
 * インストーラーの言語に依存しないよう、英語と日本語の短い文を併記する。
 * 画像はロゴタイプを含まない正式シンボル (C2) のみ。
 */

import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Slide {
        Image {
            id: symbol
            source: "welcome.png"
            width: 160; height: 160
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -60
        }
        Text {
            id: title
            anchors.horizontalCenter: symbol.horizontalCenter
            anchors.top: symbol.bottom
            anchors.topMargin: 16
            text: "MyPocketOS"
            font.pixelSize: 28
            font.bold: true
            color: "#0B2A6B"
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            anchors.horizontalCenter: symbol.horizontalCenter
            anchors.top: title.bottom
            anchors.topMargin: 12
            text: qsTr("A light, portable Linux environment.<br/>" +
                       "軽く、持ち運べる Linux 環境。<br/><br/>" +
                       "Installing. This may take a few minutes.<br/>" +
                       "インストール中です。しばらくお待ちください。")
            wrapMode: Text.WordWrap
            width: 600
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
