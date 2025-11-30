# QucikStart with Snowflake Intelligence - JA

## 概要

このハンズオンは、[Getting Started with Snowflake Intelligence](https://quickstarts.snowflake.com/guide/getting-started-with-snowflake-intelligence/index.html) をベースに、以下の最新化・日本語対応を行ったプロジェクトです。

**Snowflake Intelligence** は、組織が膨大なデータにアクセスし活用するための強力なソリューションです。AIエージェントを活用することで、従業員は安全にデータと対話し、より深いインサイトを導き出し、統一された使いやすいインターフェースからアクションを実行できます。

## 元のクイックスタートからの変更点

| 項目 | 元のクイックスタート | 本プロジェクト |
|------|---------------------|----------------|
| **言語** | 英語 | 日本語対応（シノニム・プロンプト含む） |
| **セマンティックモデル** | YAML形式 | **セマンティックビュー**（新機能） |
| **Snowflake Intelligence オブジェクト** | 未対応 | **対応**（新機能） |
| **サポートケースデータ** | 英語 | 日本語翻訳版 |
| **Git連携** | 手動アップロード | Git Repository統合 |

## 前提条件

- Snowflakeアカウント（ACCOUNTADMIN権限が必要）
- 対応リージョン（AWS US推奨）
- Cortex LLMへのアクセス

## ファイル構成

```
.
├── step1-3_setup.sql                    # Step1-3: 環境・データ・セマンティックビューのセットアップ
├── step4_create_cortex_search.txt       # Step4: Cortex Search サービス作成手順
├── step5_create_cortex_agent.txt        # Step5: Cortex Agent 作成手順
├── step5_ref_response_instructions.txt  # Step5で使用: エージェントのレスポンス指示
└── data/
    ├── marketing_campaign_metrics.csv
    ├── products.csv
    ├── sales.csv
    ├── social_media_mentions.csv
    ├── support_case_ja.csv              # 日本語版サポートケース
    └── support_cases.csv                # 英語版サポートケース
```

## セットアップ手順

### Step 1: 環境のセットアップ

`step1-3_setup.sql` を Snowsight で実行し、以下のリソースを作成します：

- **ロール**: `SNOWFLAKE_INTELLIGENCE_ADMIN`
- **データベース**: `DASH_DB_SI`
- **スキーマ**: `RETAIL`
- **ウェアハウス**: `DASH_WH_SI`（Large）
- **5つのテーブル**:
  - `MARKETING_CAMPAIGN_METRICS` - マーケティングキャンペーン指標
  - `PRODUCTS` - 製品マスタ
  - `SALES` - 売上データ
  - `SOCIAL_MEDIA` - ソーシャルメディア指標
  - `SUPPORT_CASES` - カスタマーサポートケース（日本語）

### Step 2: セマンティックビューの作成

`step1-3_setup.sql` の後半部分で、日本語シノニムを含むセマンティックビュー `Sales_And_Marketing_SV` が作成されます。

**主な特徴**:
- テーブル間のリレーションシップ定義
- 日本語シノニム（「売上」「販売」「商品」など）
- メトリクス定義（総売上、CTR、メンション数など）

### Step 3: Snowflake Intelligence オブジェクトの作成

`step1-3_setup.sql` で `SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT` が自動作成されます。

### Step 4: Cortex Search サービスの作成

Snowsight の **Data > Cortex Search** から新しいサービスを作成します。  
詳細は `step4_create_cortex_search.txt` を参照してください。

| 設定項目 | 値 |
|----------|-----|
| サービス名 | `Support_Cases` |
| 検索対象テーブル | `DASH_DB_SI.RETAIL.SUPPORT_CASES` |
| 検索列 | `TRANSCRIPT` |
| 属性列 | `TITLE`, `PRODUCT`, `DATE` |
| 埋め込みモデル | `snowflake-arctic-embed-l-v2.0` |

### Step 5: Cortex Agent の作成

Snowsight の **AI/ML > Agents** から新しいエージェントを作成します。  
詳細は `step5_create_cortex_agent.txt` を参照してください。

**エージェント構成**:
- **ツール①**: Cortex Analyst（セマンティックビュー `Sales_And_Marketing_SV`）
- **ツール②**: Cortex Search（`SUPPORT_CASES` サービス）
- **Response Instructions**: `step5_ref_response_instructions.txt` の内容を設定

## サンプル質問

エージェントに以下のような質問を試してみてください：

```
6月から8月までの製品カテゴリー別の売上動向を教えてください
```

```
最近、カスタマーサポートチケットでジャケットに関してどのような問題が報告されていますか?
```

```
フィットネスウェアの売上が7月に急増したのはなぜでしょうか？
```

## データモデル

```
┌─────────────────────────┐     ┌─────────────────┐
│ MARKETING_CAMPAIGN      │     │ PRODUCTS        │
│ METRICS                 │     │                 │
│ ─────────────────────── │     │ ─────────────── │
│ DATE                    │     │ PRODUCT_ID (PK) │
│ CATEGORY (PK)           │     │ PRODUCT_NAME    │
│ CAMPAIGN_NAME           │     │ CATEGORY        │
│ IMPRESSIONS             │     └────────┬────────┘
│ CLICKS                  │              │
└───────────┬─────────────┘              │
            │                            │
            │ CATEGORY                   │ PRODUCT_ID
            │                            │
┌───────────▼─────────────┐     ┌────────▼────────┐
│ SOCIAL_MEDIA            │     │ SALES           │
│ ─────────────────────── │     │ ─────────────── │
│ DATE                    │     │ DATE            │
│ CATEGORY                │     │ REGION          │
│ PLATFORM                │     │ PRODUCT_ID      │
│ INFLUENCER              │     │ UNITS_SOLD      │
│ MENTIONS                │     │ SALES_AMOUNT    │
└─────────────────────────┘     └─────────────────┘

┌─────────────────────────────────────────────────┐
│ SUPPORT_CASES (非構造化データ)                    │
│ ─────────────────────────────────────────────── │
│ ID, TITLE, PRODUCT, TRANSCRIPT, DATE            │
│ → Cortex Search でセマンティック検索               │
└─────────────────────────────────────────────────┘
```

## 参考リンク

- [元のクイックスタート（英語）](https://quickstarts.snowflake.com/guide/getting-started-with-snowflake-intelligence/index.html)
- [Snowflake Intelligence ドキュメント](https://docs.snowflake.com/en/user-guide/snowflake-intelligence/overview)
- [セマンティックビュー ドキュメント](https://docs.snowflake.com/en/user-guide/views-semantic)
- [Cortex Search ドキュメント](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)

## ライセンス

Apache License 2.0
