-- ============================================
-- Step 1: 環境のセットアップ
-- ============================================
-- ロール、データベース、ウェアハウスを作成し、
-- サンプルデータをロードします。
-- ============================================

use role accountadmin;

create or replace role snowflake_intelligence_admin;
grant create warehouse on account to role snowflake_intelligence_admin;
grant create database on account to role snowflake_intelligence_admin;
grant create integration on account to role snowflake_intelligence_admin;
grant create snowflake intelligence on account to role snowflake_intelligence_admin;


set current_user = (select current_user());   
grant role snowflake_intelligence_admin to user identifier($current_user);
alter user set default_role = snowflake_intelligence_admin;
alter user set default_warehouse = dash_wh_si;

use role snowflake_intelligence_admin;
create or replace database dash_db_si;
create or replace schema retail;
create or replace warehouse dash_wh_si with warehouse_size='large';

create database if not exists snowflake_intelligence;
create schema if not exists snowflake_intelligence.agents;

grant create agent on schema snowflake_intelligence.agents to role snowflake_intelligence_admin;

use database dash_db_si;
use schema retail;
use warehouse dash_wh_si;

-- ファイルフォーマットの作成
create or replace file format si_csvformat
  skip_header = 1  
  field_optionally_enclosed_by = '"'  
  type = 'csv';  
  
-- Git連携のため、API統合を作成する
CREATE OR REPLACE API INTEGRATION GIT_API_INTEGRATION
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kenokizono/')
  ENABLED = TRUE;

-- GIT統合の作成
CREATE OR REPLACE GIT REPOSITORY GIT_INTEGRATION_FOR_HANDSON
  API_INTEGRATION = git_api_integration
  ORIGIN = 'https://github.com/sfc-gh-kenokizono/quickstart-with-snowflake-intelligence-ja.git';

-- チェック
ls @GIT_INTEGRATION_FOR_HANDSON/branches/main;

-- ステージの作成
CREATE OR REPLACE STAGE dash_db_si.retail.FILE
encryption = (type = 'snowflake_sse') 
DIRECTORY = (ENABLE = TRUE)
file_format = si_csvformat;

-- Gitからファイルを持ってくる
COPY FILES INTO @dash_db_si.retail.FILE
FROM @GIT_INTEGRATION_FOR_HANDSON/branches/main/data/ PATTERN ='.*\\.csv$';

-- ============================================
-- テーブル作成とデータロード（5テーブル）
-- ============================================

-- [1/5] MARKETING_CAMPAIGN_METRICS: マーケティングキャンペーン指標
-- インプレッション数、クリック数などのキャンペーン効果を記録
create or replace table marketing_campaign_metrics (
  date date,
  category varchar(16777216),
  campaign_name varchar(16777216),
  impressions number(38,0),
  clicks number(38,0)
);

copy into marketing_campaign_metrics  
  from @dash_db_si.retail.FILE/marketing_campaign_metrics.csv;

-- [2/5] PRODUCTS: 製品マスタ
-- 商品ID、商品名、カテゴリの製品情報
create or replace table products (
  product_id number(38,0),
  product_name varchar(16777216),
  category varchar(16777216)
);

copy into products  
  from @dash_db_si.retail.FILE/products.csv;

-- [3/5] SALES: 売上データ
-- 日付、地域、商品ごとの販売数量と売上金額
create or replace table sales (
  date date,
  region varchar(16777216),
  product_id number(38,0),
  units_sold number(38,0),
  sales_amount number(38,2)
);

copy into sales  
  from @dash_db_si.retail.FILE/sales.csv;

-- [4/5] SOCIAL_MEDIA: ソーシャルメディア指標
-- プラットフォーム別、インフルエンサー別のメンション数
create or replace table social_media (
  date date,
  category varchar(16777216),
  platform varchar(16777216),
  influencer varchar(16777216),
  mentions number(38,0)
);

copy into social_media  
  from @dash_db_si.retail.FILE/social_media_mentions.csv;

-- [5/5] SUPPORT_CASES: カスタマーサポートケース（日本語）
-- お客様との会話トランスクリプト（非構造化データ）
-- → Step4でCortex Searchの検索対象になります
create or replace table support_cases (
  id varchar(16777216),
  title varchar(16777216),
  product varchar(16777216),
  transcript varchar(16777216),
  date date
);

copy into support_cases  
  from @dash_db_si.retail.FILE/support_case_ja.csv;


-- クロスリージョン設定
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';


-- ============================================
-- Step 2: セマンティックビューの作成
-- ============================================
-- 日本語シノニムを含むセマンティックビューを作成します。
-- テーブル間のリレーションシップ、メトリクス、
-- ディメンションを定義します。
-- ============================================

CREATE OR REPLACE SEMANTIC VIEW DASH_DB_SI.RETAIL.Sales_And_Marketing_SV

-- ----------------------------------------
-- TABLES: 使用するテーブルを定義
-- セマンティックビューに含めるテーブルと、
-- 日本語シノニム（別名）を設定します
-- ----------------------------------------
TABLES (
    MARKETING_CAMPAIGN_METRICS AS DASH_DB_SI.RETAIL.MARKETING_CAMPAIGN_METRICS
        PRIMARY KEY (CATEGORY)
        WITH SYNONYMS ('マーケティングキャンペーン', '広告キャンペーン', '宣伝活動', 'キャンペーン')
        COMMENT = 'マーケティングキャンペーンのメトリクス',
    
    PRODUCTS AS DASH_DB_SI.RETAIL.PRODUCTS
        PRIMARY KEY (PRODUCT_ID)
        WITH SYNONYMS ('商品カタログ', '製品一覧', '商品', '製品', 'アイテム')
        COMMENT = '製品マスタデータ',
    
    SALES AS DASH_DB_SI.RETAIL.SALES
        WITH SYNONYMS ('売上取引', '販売', '取引', '注文', 'オーダー', '売上データ')
        COMMENT = '売上取引データ',
    
    SOCIAL_MEDIA AS DASH_DB_SI.RETAIL.SOCIAL_MEDIA
        WITH SYNONYMS ('ソーシャルメディア', 'SNS', 'ソーシャル', 'SNSデータ', 'ソーシャル指標')
        COMMENT = 'ソーシャルメディアデータ'
)

-- ----------------------------------------
-- RELATIONSHIPS: テーブル間の結合関係を定義
-- JOINの条件を事前に設定しておくことで、
-- AIが適切にテーブルを結合できます
-- ----------------------------------------
RELATIONSHIPS (
    SALES_TO_PRODUCT AS SALES (PRODUCT_ID) REFERENCES PRODUCTS,
    MARKETING_TO_SOCIAL AS SOCIAL_MEDIA (CATEGORY) REFERENCES MARKETING_CAMPAIGN_METRICS
)

-- ----------------------------------------
-- FACTS: 集計対象の数値カラムを定義
-- SUM, AVG, COUNTなどで集計される
-- 「測定値」となるカラムを指定します
-- ----------------------------------------
FACTS (
    MARKETING_CAMPAIGN_METRICS.clicks AS CLICKS
        COMMENT = 'マーケティングキャンペーンの一環として、ユーザーが広告やプロモーションリンクをクリックした総回数',
    
    MARKETING_CAMPAIGN_METRICS.impressions AS IMPRESSIONS
        COMMENT = 'マーケティングキャンペーン中に広告がユーザーに表示された総回数',
    
    SALES.sales_amount AS SALES_AMOUNT
        COMMENT = '取引や注文から生成された総売上金額',
    
    SALES.units_sold AS UNITS_SOLD
        COMMENT = '販売された製品の総数量',
    
    SOCIAL_MEDIA.mentions AS MENTIONS
        COMMENT = 'ソーシャルメディアプラットフォーム上でブランド、製品、またはキーワードが言及された回数'
)

-- ----------------------------------------
-- DIMENSIONS: 分析軸（グループ化キー）を定義
-- 「〜別」「〜ごと」で分析する際の
-- 切り口となるカラムを指定します
-- ----------------------------------------
DIMENSIONS (
    MARKETING_CAMPAIGN_METRICS.campaign_name AS MARKETING_CAMPAIGN_METRICS.CAMPAIGN_NAME
        WITH SYNONYMS ('キャンペーン名', '広告名', '宣伝名', 'プロモーション名', 'キャンペーンタイトル', '広告タイトル')
        COMMENT = 'マーケティングキャンペーンの名前',
    
    MARKETING_CAMPAIGN_METRICS.marketing_category AS MARKETING_CAMPAIGN_METRICS.CATEGORY
        WITH SYNONYMS ('カテゴリ', '分類', '区分', 'ジャンル', '種類', 'タイプ', '分野')
        COMMENT = 'マーケティングキャンペーンのカテゴリ',
    
    MARKETING_CAMPAIGN_METRICS.marketing_date AS MARKETING_CAMPAIGN_METRICS.DATE
        WITH SYNONYMS ('日付', '日時', '年月日', 'キャンペーン日', '実施日', '配信日')
        COMMENT = 'マーケティングキャンペーンの指標が記録された日付',
    
    PRODUCTS.product_category AS PRODUCTS.CATEGORY
        WITH SYNONYMS ('商品カテゴリ', '製品カテゴリ', '商品分類', '製品分類', '商品種別', 'ジャンル')
        COMMENT = '販売される製品のタイプ',
    
    PRODUCTS.product_id AS PRODUCTS.PRODUCT_ID
        WITH SYNONYMS ('商品ID', '製品ID', 'アイテムID', '商品コード', '製品コード', 'SKU', 'JAN')
        COMMENT = 'カタログ内の各製品の一意識別子',
    
    PRODUCTS.product_name AS PRODUCTS.PRODUCT_NAME
        WITH SYNONYMS ('商品名', '製品名', 'アイテム名', '商品タイトル', '製品タイトル', '商品説明')
        COMMENT = '販売される製品の名前',
    
    SALES.sales_product_id AS SALES.PRODUCT_ID
        WITH SYNONYMS ('売上商品ID', '販売商品ID', '商品ID', '製品ID', 'SKU')
        COMMENT = '販売された製品の一意識別子',
    
    SALES.region AS SALES.REGION
        WITH SYNONYMS ('地域', 'エリア', '地区', '営業区域', '販売地域', '市場', '拠点')
        COMMENT = '売上が作られた地理的地域',
    
    SALES.sales_date AS SALES.DATE
        WITH SYNONYMS ('売上日', '販売日', '取引日', '注文日', '日付', '年月日')
        COMMENT = '売上日。取引が発生したカレンダー日付',
    
    SOCIAL_MEDIA.social_category AS SOCIAL_MEDIA.CATEGORY
        WITH SYNONYMS ('SNSカテゴリ', 'ソーシャルカテゴリ', '分類', 'ジャンル', '種別')
        COMMENT = 'ソーシャルメディアコンテンツのカテゴリ',
    
    SOCIAL_MEDIA.influencer AS SOCIAL_MEDIA.INFLUENCER
        WITH SYNONYMS ('インフルエンサー', 'インフルエンサー名', 'クリエイター', 'コンテンツクリエイター', 'ブランドアンバサダー')
        COMMENT = 'ソーシャルメディアインフルエンサーの名前',
    
    SOCIAL_MEDIA.platform AS SOCIAL_MEDIA.PLATFORM
        WITH SYNONYMS ('プラットフォーム', 'SNSプラットフォーム', 'メディア', 'チャネル', 'ネットワーク')
        COMMENT = 'ソーシャルメディアプラットフォーム',
    
    SOCIAL_MEDIA.social_date AS SOCIAL_MEDIA.DATE
        WITH SYNONYMS ('SNS日付', 'ソーシャル日付', '投稿日', '配信日', '日付', '年月日')
        COMMENT = 'ソーシャルメディアデータが収集された日付'
)

-- ----------------------------------------
-- METRICS: 計算式（集計ロジック）を定義
-- よく使う集計パターン（合計、平均、率など）を
-- 事前に定義しておきます
-- ----------------------------------------
METRICS (
    MARKETING_CAMPAIGN_METRICS.total_clicks AS SUM(CLICKS)
        WITH SYNONYMS ('総クリック数', 'クリック合計', 'クリック数', 'トータルクリック', 'クリック総数')
        COMMENT = '総クリック数',
    
    MARKETING_CAMPAIGN_METRICS.total_impressions AS SUM(IMPRESSIONS)
        WITH SYNONYMS ('総インプレッション数', 'インプレッション合計', 'インプレッション数', '表示回数', '総表示回数')
        COMMENT = '総インプレッション数',
    
    MARKETING_CAMPAIGN_METRICS.click_through_rate AS DIV0(SUM(CLICKS), SUM(IMPRESSIONS))
        WITH SYNONYMS ('クリック率', 'CTR', 'クリックスルー率', 'クリック通過率')
        COMMENT = 'クリック率（CTR）',
    
    SALES.total_sales_amount AS SUM(SALES_AMOUNT)
        WITH SYNONYMS ('総売上金額', '売上合計', '総売上', '売上総額', '売上高', '総収益', '収益合計')
        COMMENT = '総売上金額',
    
    SALES.total_units_sold AS SUM(UNITS_SOLD)
        WITH SYNONYMS ('総販売数量', '販売数量合計', '総販売個数', '販売合計数', '売上数量', '販売総数')
        COMMENT = '総販売数量',
    
    SALES.average_sales_amount AS AVG(SALES_AMOUNT)
        WITH SYNONYMS ('平均売上金額', '売上平均', '平均売上', '平均収益', '売上単価', '平均単価')
        COMMENT = '平均売上金額',
    
    SOCIAL_MEDIA.total_mentions AS SUM(MENTIONS)
        WITH SYNONYMS ('総メンション数', 'メンション合計', 'メンション数', '言及回数', '言及総数', 'バズ数')
        COMMENT = '総メンション数'
)
COMMENT = 'セールスとマーケティングデータのセマンティックビュー';


-- ============================================
-- 💡 Step 2 補足: Snowsightでセマンティックビューを確認
-- ============================================
-- 
-- 【操作手順】
-- 1. Snowsight → Data → Databases → DASH_DB_SI → RETAIL 
--    → Views → Sales_And_Marketing_SV を選択
-- 2. 「Playground」タブで質問を試してみましょう
--    例: 「製品カテゴリ別の売上を教えて」
--
-- 【Verified Queries（検証済みクエリ）について】
-- よく使う質問パターンは Verified Queries に登録しましょう！
-- → 正しい結果が表示されたら「Add to Verified Queries」をクリック
-- → 次回から同じ質問に一発で正確な回答を返します
--
-- ============================================


-- ============================================
-- Step 3: Snowflake Intelligence オブジェクトの作成
-- ============================================
-- Snowflake Intelligence オブジェクトを作成し、
-- 必要な権限を付与します。
-- ============================================

CREATE OR REPLACE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE snowflake_intelligence_admin;
GRANT MODIFY ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE snowflake_intelligence_admin;


-- ============================================
-- セットアップ完了
-- ============================================
select 'Congratulations! Step 1-3 setup has completed successfully!' as status;


-- ============================================
-- クリーンアップ（ハンズオン終了後に実行）
-- ============================================
-- 注意: 以下のコマンドはハンズオン環境を完全に削除します。
-- 必要な場合のみ、ACCOUNTADMINロールで実行してください。
-- ============================================

/*

USE ROLE ACCOUNTADMIN;

-- Step 5で作成したCortex Agent
DROP AGENT IF EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS.SALES_AI;

-- Step 4で作成したCortex Search サービス
DROP CORTEX SEARCH SERVICE IF EXISTS DASH_DB_SI.RETAIL.SUPPORT_CASES;

-- Step 3で作成したSnowflake Intelligence オブジェクト
DROP SNOWFLAKE INTELLIGENCE IF EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- Step 1で作成したリソース
DROP DATABASE IF EXISTS DASH_DB_SI;
DROP DATABASE IF EXISTS SNOWFLAKE_INTELLIGENCE;
DROP WAREHOUSE IF EXISTS DASH_WH_SI;

-- Git連携
DROP API INTEGRATION IF EXISTS GIT_API_INTEGRATION;

-- ロールの削除（最後に実行）
DROP ROLE IF EXISTS SNOWFLAKE_INTELLIGENCE_ADMIN;

SELECT 'Cleanup completed successfully!' AS status;

*/
