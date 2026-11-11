# stackchan-muse-hub

M5Stack CoreS3（StackChan）を Meta の **Muse Gadget** として動かす hub ファームを、ビルド・パッケージ・書き込みするためのリポジトリです。

hub 本体は GOB52 氏の [EvenG2-Muse-Hub-M5](https://github.com/GOB52/EvenG2-Muse-Hub-M5) にあります。このリポジトリには **CoreS3 用の設定・スクリプト・手順だけ** を置いており、hub と SDK のソースは submodule として参照しています（中身は変更しません）。

## 構成

```
.
├── hub/                              # submodule: GOB52/EvenG2-Muse-Hub-M5（ad71dc7 に固定）
│   └── hub/                          # ファームのプロジェクトディレクトリ（CMakeLists.txt）
│       ├── patches/                  # SDK に当てるパッチ
│       ├── tools/apply_patches.sh    # パッチ適用（冪等）
│       └── third_party/muse-gadget-sdk/   # submodule: Muse Gadget SDK（463bd2a、esp32/ がデバイス SDK）
├── config/sdkconfig.cores3           # CoreS3 用の sdkconfig 差分（16 MB flash / 8 MB PSRAM）
├── scripts/build.sh                  # build / package
├── sdkconfig.local                   # 各自で作成（Git 管理外。relay トークンを入れる）
├── build/cores3/                     # ビルド出力（Git 管理外）
└── dist/cores3-hub-package/          # 書き込み用パッケージ（Git 管理外）
```

clone するときは submodule ごと取得してください。

```sh
git clone --recursive <this-repo-url>
# 既に clone 済みなら
git submodule update --init --recursive
```

## 前提

- ビルド機（Linux）：ESP-IDF **v6.0.3**（既定のパスは `/home/ubuntu/esp/esp-idf-v6`。別の場所なら `IDF_PATH` で指定）
- 書き込み機（Mac）：Python 3 と esptool

  ```sh
  pip install esptool
  ```

## sdkconfig.local

リポジトリ直下に `sdkconfig.local` を作り、hub の relay トークンを設定します。このファイルは `.gitignore` 済みです。**中身をコミットしたり、チャットに貼ったりしないでください。**

```
CONFIG_HUB_RELAY_TOKEN="<任意の長いランダム文字列>"
```

`sdkconfig.local` が無いと `scripts/build.sh build` はエラーで止まります。

> relay トークンはファーム（`muse-gadget.bin`）に埋め込まれます。`build/` と `dist/` も秘密情報として扱い、公開や共有をしないでください。

## ビルド

```sh
scripts/build.sh build     # パッチ適用 → build/cores3 にビルド
scripts/build.sh package   # dist/cores3-hub-package/ にまとめる
```

`build` では次の処理を行います。

1. `$IDF_PATH/export.sh` を読み込む
2. `hub/hub/tools/apply_patches.sh` で SDK にパッチを当てる（当てたパッチは SDK submodule の作業ツリーに差分として残ります）
3. `idf.py -C hub/hub -B build/cores3 -DIDF_TARGET=esp32s3 ...` でビルドする。sdkconfig のデフォルトは次の順に重ねます（後のものが優先）。
   `sdkconfig.defaults` → `devices/sdkconfig.muse` → `devices/sdkconfig.muse-m5stack-cores3` → `config/sdkconfig.cores3` → `sdkconfig.local`

> sdkconfig のデフォルトが使われるのは、sdkconfig を新しく作るときだけです。`config/sdkconfig.cores3` や `sdkconfig.local` を変更したら、`build/cores3/sdkconfig` を削除してからビルドし直してください。

ビルド中に出る `No SDK token` の警告は想定どおりです。SDK トークンはファームに埋め込まず、書き込み後にシリアルから設定します（後述）。

`package` では、`bootloader.bin`、`partition-table.bin`、`ota_data_initial.bin`、`muse-gadget.bin`、`SHA256SUMS`、`flash.sh` を `dist/cores3-hub-package/` にまとめます。

## Mac での書き込み

```sh
scp -r <build-host>:<repo>/dist/cores3-hub-package .
cd cores3-hub-package
./flash.sh /dev/cu.usbmodemXXXX           # 通常の書き込み
./flash.sh --erase /dev/cu.usbmodemXXXX   # フラッシュ全体を消去してから書き込む
```

- `flash.sh` は、まず `shasum -a 256 -c SHA256SUMS` でファイルを検証してから esptool で書き込みます。
- `--erase` を付けると、書き込み前に `erase-flash` を実行します（既定はオフ）。NVS も消えるので、ペアリング・Wi-Fi・SDK トークンの設定はやり直しになります。
- esptool が接続できない場合は、**RST を 3 秒長押し**（緑 LED が点灯）してブートローダーモードにしてから再実行してください。
- ポート名は `ls /dev/cu.usbmodem*` で確認できます。

## SDK トークンの設定

SDK トークンは **チャットやリポジトリに書かないでください。**

1. [gadgets.muse.ai](https://gadgets.muse.ai) の **Account > SDK tokens** でトークンを発行します。
2. シリアルモニタ（例：`python3 -m serial.tools.miniterm /dev/cu.usbmodemXXXX 115200`）で CoreS3 に接続し、次のように入力します。

   ```
   >sdk_token=mgst_…
   ```

## ペアリング

1. Muse アプリで **Developer mode** を有効にします。
2. **Add Device** を選び、`MuseGadget-XXXXXX` を選択します。
3. Wi-Fi は、互換性を優先して iPhone の **インターネット共有** を使うことを推奨します（「互換性を優先」をオンにすると 2.4 GHz になります）。
4. CoreS3 にペアリングの確認が表示されたら、PWR ボタンで承認します。

## Even AI の設定（Even Realities アプリ）

| 項目 | 値 |
| --- | --- |
| Endpoint | `http://muse-hub.local:8787/v1/chat/completions` |
| API Key | `sdkconfig.local` の `CONFIG_HUB_RELAY_TOKEN` と同じ値 |

API Key の値は、この README を含めどこにも書かないでください。

### iPhone のローカルネットワーク許可

iPhone の **設定 > プライバシーとセキュリティ > ローカルネットワーク** で **Even Realities** をオンにしてください。オフのままだと `muse-hub.local` に接続できません。

## CoreS3 の操作

- **PWR ボタン**：push-to-talk と、ペアリングの確認
- **設定画面**：画面を左にスワイプ

## 注意

- これは **CoreS3 用** の設定です。StickS3 用ではありません（StickS3 用は hub 本体の `hub/hub/tools/build.sh` と `sdkconfig.hub` を使います）。パーティションは SDK の `partitions_muse.csv`（16 MB flash、4 MB のアプリ領域 × 2）を使います。
- 書き込むと、CoreS3 にある既存のファーム（jeeves-stackchan など）は **上書きされます**。
- hub は **GOB52 氏の個人プロジェクト** で、Muse の公式プロジェクトではありません。
- Muse Gadget SDK は Meta が Apache-2.0 で公開している SDK です。ライセンスは各リポジトリ（hub、SDK）の記載に従ってください。
