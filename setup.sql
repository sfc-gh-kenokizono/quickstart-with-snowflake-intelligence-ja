-- データベースやウェアハウス、ロールの作成など
use role accountadmin;

create or replace role snowflake_intelligence_admin;
grant create warehouse on account to role snowflake_intelligence_admin;
grant create database on account to role snowflake_intelligence_admin;
grant create integration on account to role snowflake_intelligence_admin;

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

-- テーブル作成とデータロードを5つ分実施
create or replace table marketing_campaign_metrics (
  date date,
  category varchar(16777216),
  campaign_name varchar(16777216),
  impressions number(38,0),
  clicks number(38,0)
);

copy into marketing_campaign_metrics  
  from @dash_db_si.retail.FILE/marketing_campaign_metrics.csv;
  
create or replace table products (
  product_id number(38,0),
  product_name varchar(16777216),
  category varchar(16777216)
);

copy into products  
  from @dash_db_si.retail.FILE/products.csv;

create or replace table sales (
  date date,
  region varchar(16777216),
  product_id number(38,0),
  units_sold number(38,0),
  sales_amount number(38,2)
);

copy into sales  
  from @dash_db_si.retail.FILE/sales.csv;


create or replace table social_media (
  date date,
  category varchar(16777216),
  platform varchar(16777216),
  influencer varchar(16777216),
  mentions number(38,0)
);

copy into social_media  
  from @dash_db_si.retail.FILE/social_media_mentions.csv;

  
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

select 'Congratulations! Snowflake Intelligence setup has completed successfully!' as status;


-------------------------------


-- セマンティックビュー作成
CREATE OR REPLACE SEMANTIC VIEW DASH_DB_SI.RETAIL.Sales_And_Marketing_SV
TABLES (
    MARKETING_CAMPAIGN_METRICS AS DASH_DB_SI.RETAIL.MARKETING_CAMPAIGN_METRICS
        PRIMARY KEY (CATEGORY)
        WITH SYNONYMS ('marketing campaigns', 'ad campaigns')
        COMMENT = 'マーケティングキャンペーンのメトリクス',
    
    PRODUCTS AS DASH_DB_SI.RETAIL.PRODUCTS
        PRIMARY KEY (PRODUCT_ID)
        WITH SYNONYMS ('product catalog', 'items')
        COMMENT = '製品マスタデータ',
    
    SALES AS DASH_DB_SI.RETAIL.SALES
        WITH SYNONYMS ('transactions', 'orders')
        COMMENT = '売上取引データ',
    
    SOCIAL_MEDIA AS DASH_DB_SI.RETAIL.SOCIAL_MEDIA
        WITH SYNONYMS ('social media metrics', 'social data')
        COMMENT = 'ソーシャルメディアデータ'
)
RELATIONSHIPS (
    SALES_TO_PRODUCT AS SALES (PRODUCT_ID) REFERENCES PRODUCTS,
    MARKETING_TO_SOCIAL AS SOCIAL_MEDIA (CATEGORY) REFERENCES MARKETING_CAMPAIGN_METRICS
)
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
DIMENSIONS (
    MARKETING_CAMPAIGN_METRICS.campaign_name AS MARKETING_CAMPAIGN_METRICS.CAMPAIGN_NAME
        WITH SYNONYMS ('ad_campaign', 'ad_title', 'advertisement_name', 'campaign_title', 'marketing_campaign', 'promo_name', 'promotion_name')
        COMMENT = 'マーケティングキャンペーンの名前',
    
    MARKETING_CAMPAIGN_METRICS.marketing_category AS MARKETING_CAMPAIGN_METRICS.CATEGORY
        WITH SYNONYMS ('class', 'classification', 'genre', 'group', 'kind', 'label', 'sort', 'type')
        COMMENT = 'マーケティングキャンペーンのカテゴリ',
    
    MARKETING_CAMPAIGN_METRICS.marketing_date AS MARKETING_CAMPAIGN_METRICS.DATE
        WITH SYNONYMS ('calendar_date', 'calendar_day', 'datestamp', 'day', 'schedule_date', 'timestamp')
        COMMENT = 'マーケティングキャンペーンの指標が記録された日付',
    
    PRODUCTS.product_category AS PRODUCTS.CATEGORY
        WITH SYNONYMS ('product_class', 'product_classification', 'product_genre', 'product_group', 'product_type')
        COMMENT = '販売される製品のタイプ',
    
    PRODUCTS.product_id AS PRODUCTS.PRODUCT_ID
        WITH SYNONYMS ('item_id', 'item_number', 'product_code', 'sku')
        COMMENT = 'カタログ内の各製品の一意識別子',
    
    PRODUCTS.product_name AS PRODUCTS.PRODUCT_NAME
        WITH SYNONYMS ('item_description', 'item_name', 'product_label', 'product_title')
        COMMENT = '販売される製品の名前',
    
    SALES.sales_product_id AS SALES.PRODUCT_ID
        WITH SYNONYMS ('item_id', 'product_code', 'sku')
        COMMENT = '販売された製品の一意識別子',
    
    SALES.region AS SALES.REGION
        WITH SYNONYMS ('area', 'district', 'geographic_area', 'location', 'territory', 'zone')
        COMMENT = '売上が作られた地理的地域',
    
    SALES.sales_date AS SALES.DATE
        WITH SYNONYMS ('calendar_date', 'day', 'date_column', 'timestamp')
        COMMENT = '売上日。取引が発生したカレンダー日付',
    
    SOCIAL_MEDIA.social_category AS SOCIAL_MEDIA.CATEGORY
        WITH SYNONYMS ('class', 'classification', 'type')
        COMMENT = 'ソーシャルメディアコンテンツのカテゴリ',
    
    SOCIAL_MEDIA.influencer AS SOCIAL_MEDIA.INFLUENCER
        WITH SYNONYMS ('brand_ambassador', 'content_creator', 'social_media_personality')
        COMMENT = 'ソーシャルメディアインフルエンサーの名前',
    
    SOCIAL_MEDIA.platform AS SOCIAL_MEDIA.PLATFORM
        WITH SYNONYMS ('channel', 'network', 'social_media_channel')
        COMMENT = 'ソーシャルメディアプラットフォーム',
    
    SOCIAL_MEDIA.social_date AS SOCIAL_MEDIA.DATE
        WITH SYNONYMS ('calendar_date', 'posting_date', 'timestamp')
        COMMENT = 'ソーシャルメディアデータが収集された日付'
)
METRICS (
    MARKETING_CAMPAIGN_METRICS.total_clicks AS SUM(CLICKS)
        WITH SYNONYMS ('total clicks', 'click count')
        COMMENT = '総クリック数',
    
    MARKETING_CAMPAIGN_METRICS.total_impressions AS SUM(IMPRESSIONS)
        WITH SYNONYMS ('total impressions', 'impression count')
        COMMENT = '総インプレッション数',
    
    MARKETING_CAMPAIGN_METRICS.click_through_rate AS DIV0(SUM(CLICKS), SUM(IMPRESSIONS))
        WITH SYNONYMS ('CTR', 'click rate')
        COMMENT = 'クリック率（CTR）',
    
    SALES.total_sales_amount AS SUM(SALES_AMOUNT)
        WITH SYNONYMS ('total sales', 'revenue')
        COMMENT = '総売上金額',
    
    SALES.total_units_sold AS SUM(UNITS_SOLD)
        WITH SYNONYMS ('total units', 'quantity sold')
        COMMENT = '総販売数量',
    
    SALES.average_sales_amount AS AVG(SALES_AMOUNT)
        WITH SYNONYMS ('avg sales', 'average revenue')
        COMMENT = '平均売上金額',
    
    SOCIAL_MEDIA.total_mentions AS SUM(MENTIONS)
        WITH SYNONYMS ('total mentions', 'mention count')
        COMMENT = '総メンション数'
)
COMMENT = 'セールスとマーケティングデータのセマンティックビュー';

























