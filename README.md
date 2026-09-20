# Fuel Guide — Forerunner 265で補給の判断材料を集める

標準のラン記録に追加するConnect IQのデータフィールドと、Jev APIを呼ぶローカル中継サーバーの試作です。心拍・速度・ピッチの変化を集計し、補給計画を見直す候補をウォッチに表示します。

**初期状態はモックです。Jevへの送信や課金は発生しません。** 疲労や脱水の診断、30分以内のガス欠確率、補給量の決定には使えません。画面の候補は実験用の参考表示です。

当面は自分のForerunner 265へUSB経由で入れる使い方を前提にしています。ストア公開は不要です。中継サーバーは「ローカルで試す」、ウォッチへの導入は「自分のウォッチで使う」を参照してください。

## データはウォッチで集計し、中継経由でJevに送る

```text
Forerunner 265 / 標準のラン記録
  └─ CIQ Data Field: 毎秒取得 → 5秒ごとに保存 → 最大10分の集計
       └─ Garmin Connect / スマートフォンのネット接続
            └─ 自分のHTTPS中継サーバー: 初期値60秒間隔
                 └─ TypeSafe Jev API
            ← 検証済みの応答だけをウォッチの参考表示に反映
```

ウォッチ側はMonkey C、中継側はTypeScriptです。Web UIを持たないため、React・Vite+は使用していません。依存関係とNodeの指定はpackage.jsonで管理します。

| データ | 扱い |
| --- | --- |
| 心拍 | Activity.Info.currentHeartRate、bpm。欠損はnull |
| 速度 | currentSpeed、m/s。画面ではペースに換算可能 |
| ピッチ | currentCadence、Garmin APIのrpmを保持。推測で2倍にしない |
| 経過時間 | timerTime、ミリ秒を秒に変換 |
| 気温 | 初版はnull。手首温度を外気温として代用しない |
| 心拍ドリフト | 最初と直近の区間で心拍/速度の比を比較。坂や気温などの影響を分離した指標ではない |
| ピッチの変動 | 変動係数（標準偏差÷平均）。欠損を0として計算しない |

JevのScoreは記述した段階の評点で、発症確率ではありません。Noulは0〜1の値であり、別のconfidenceフィールドはありません。この試作では0.85を超える候補が続いたときに表示を許可し、15分間は次の通知候補を抑えます。摂取履歴や個人の補給計画は未入力なので、ジェルの個数や水分量は指示しません。

## ローカルで試す

Nodeとpnpmの指定バージョンはpackage.jsonを参照してください。Garmin SDK・Java・Node・pnpm本体はこのリポジトリに含めていません。各ツールをインストールしてから、以下のコマンドで起動します。

```sh
git clone https://github.com/kuromoka/garmin-fuel-guide.git
cd garmin-fuel-guide
pnpm install
test -f .env || cp .env.example .env
```

.envのRELAY_TOKENに自分で生成した値を設定します。例えば `openssl rand -hex 24` の出力を使えます。JEV_MODEはmockのままにします。

```sh
pnpm check
pnpm start
```

別のターミナルで `curl http://127.0.0.1:8787/health` を実行します。モックの応答は通信と表示を試すための固定ルールであり、Jevの推論結果ではありません。テストは外部APIを呼びません。

## 自分のウォッチで使う

ストアを使わず、個人設定を含めた実行ファイルを作成します。サイドロードしたアプリは、スマホのConnect IQアプリから設定を変更できません。[Garmin公式FAQ](https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq#app-settings)

```sh
test -f .personal.json || cp .personal.example.json .personal.json
pnpm build:personal
# この開発環境では bash scripts/dev.sh build:personal でも実行できます。
```

`.personal.json` の `relayUrl` が空なら、通信しない版を作ります。Jev連携を使うときは、自分のHTTPS中継先のURLを設定します。末尾の `/evaluate` はアプリが付けるため、設定には含めません。トークンは中継と同じ `.env` の `RELAY_TOKEN` を使います。JevのAPIキーは中継側だけに置き、ウォッチへ埋め込みません。

| 個人設定 | 内容 |
| --- | --- |
| relayUrl | HTTPS中継先。空文字なら通信なし |
| relayIntervalSeconds | 送信間隔。30〜600秒、初期値60秒 |

ビルドには、下の「Forerunner 265向けにビルドする」で説明するSDK・Java・署名鍵が必要です。

### Macから実機へ転送する

1. Forerunner 265をデータ転送できるUSBケーブルでMacに接続します。Garmin Expressが起動していたら終了します。
2. [OpenMTP](https://openmtp.ganeshrvel.com/)をインストールして開きます。Macからウォッチ内のファイルを扱うために使います。Finderにウォッチが表示されない場合も、OpenMTPで接続を確認してください。
3. リポジトリ内の `ciq/build/FuelGuide-personal.prg` を、ウォッチ側の `GARMIN/APPS` フォルダーへコピーします。転送するのは、このPRGファイル1つです。
4. 転送が完了してからUSB接続を解除します。
5. ウォッチで `UP長押し → アクティビティ＆アプリ → ラン → ラン設定 → トレーニングページ` を開きます。
6. カスタムデータページを追加し、レイアウトを1項目にします。データ項目の `Connect IQ → Fuel Guide` を選びます。表記はウォッチのソフトウェアによって異なる場合があります。

Fuel Guideはラン画面に追加するデータ項目です。独立したアプリとして起動する形式ではありません。`relayUrl` が空のビルドでは、`RELAY OFF` の表示は正常です。Jev連携を使うには、HTTPS中継先を設定して再ビルド・再転送します。

この転送手順は公式資料を基にしています。このプロジェクトでの実機転送はまだ未確認です。[Garmin公式のサイドロード案内](https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq)、[Forerunner 265のトレーニングページ設定](https://www8.garmin.com/manuals-apac/webhelp/forerunner265series/JA-JP/GUID-5FE174F6-2099-4194-AE6F-5806D91F94DF-2964.html)を参照してください。

個人設定・生成したリソース・実行ファイルはGit管理から除外します。通信を有効にした実行ファイルには中継トークンが入るため、自分のウォッチへの転送に使ってください。設定変更後は再ビルド・再転送が必要です。

## Forerunner 265向けにビルドする

1. [Garmin公式SDK Manager](https://developer.garmin.com/connect-iq/sdk/)でログインし、SDKとForerunner 265の機種データを取得します。機種IDは `fr265` です。
2. SDKの場所と開発用署名鍵を設定します。SDK・署名鍵はリポジトリに含まれないため、自分の環境で用意します。SDK同梱のmonkeycを実行できるJava環境が必要です。
3. ビルドコマンドを実行します。

```sh
# CIQ_SDK_HOMEはbin/monkeycを含むSDKのディレクトリ
# SDK Managerの現在のSDK設定を自動検出します。
# 別の場所に置いた場合だけ CIQ_SDK_HOME を指定してください。
# 以下の鍵生成は .tools/developer_key.der がない場合だけ実行する。
# 既存の鍵を上書きせずに使用する。
mkdir -p .tools
if [ ! -f .tools/developer_key.der ]; then
  openssl genrsa -out .tools/developer_key.pem 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER \
    -in .tools/developer_key.pem -out .tools/developer_key.der -nocrypt
  chmod 600 .tools/developer_key.*
fi
export CIQ_DEVELOPER_KEY="$PWD/.tools/developer_key.der"
pnpm build:ciq
```

生成先は `ciq/build/FuelGuide.prg` です。実機への転送とラン画面への追加は、ビルド成功後に行います。SDKのシミュレーターで先に確認し、実機では1フィールドのデータ画面に追加して表示を確認してください。署名鍵やAPIキーをリポジトリにコミットしないでください。

## ウォッチから通信するにはHTTPS中継が必要

ローカルの `127.0.0.1` は、スマートフォンから見た開発用Macのアドレスにはなりません。実機テストでは、スマートフォンから到達できるHTTPSの中継先を用意し、`.personal.json` のURLと `.env` のRELAY_TOKENを設定して自分用にビルドします。HTTPS中継先の公開やトンネルの作成は、別途設定が必要です。

Jevで試す場合は、中継の.envに `JEV_MODE=jev` と `TYPESAFE_API_KEY` を設定して再起動します。これ以降は心拍・速度・ピッチ・経過時間とその集計がTypeSafeへ送信され、API利用料が発生します。位置情報・氏名・Garminアカウント情報は送信対象に含めません。中継はデータをファイル保存せず、通知制御用の状態をメモリ内に保持します。

通信の最短間隔は30秒、Jev呼び出しは1プロセス最大120回です。失敗時の自動再試行を避け、古い応答や順序の逆転した応答から通知候補を作らないようにしています。上限は研究用の設定であり、30秒や60秒の間隔を生理学的に検証したものではありません。

## 初版に含まれないもの

- 外気温の取得、摂取量・補給時刻の記録、個人の補給計画との照合
- イヤホンへの音声案内、振動による通知、給水所までの地理的なルート案内
- 校正済みのガス欠確率、危険度診断、オフラインで動くJevモデル
- 公開サーバーへのデプロイ、CIQストア公開、電池消費の実測

## 仕様を確認する

- [Garmin DataField — 毎秒のcompute](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html)
- [Garmin Activity.Info — センサー値と単位](https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html)
- [Jev公式発表](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- [TypeSafe Quick start — リクエストと応答](https://docs.typesafe.ai/introduction/quickstart)
- [Score](https://docs.typesafe.ai/primitives/score) / [Noul](https://docs.typesafe.ai/primitives/noul)

Data Fieldは標準アクティビティ画面に追加する拡張表示、StateはJevへ渡す評価対象データ、relayはウォッチとJevの間で認証・検証を行う中継です。

不具合を報告する際は、失敗したコマンドとエラーを添えてください。APIキーやトークンは含めないでください。

## 確認済みの範囲

Node 26.9.0で型チェックと21件のテスト、SDK 9.2.0でForerunner 265向けビルドが成功しました。シミュレーターでは初期画面の表示を確認しています。実Jev API接続、実機転送、実走行、電池消費は未確認です。

更新日: 2026-09-21
