-- ============================================================================
-- 【Internal】全環境一括セットアップ
-- ============================================================================
-- このスクリプトは、ハンズオン環境を一発で構築するための内部用SQLです。
-- Step 1-5 の全てを自動で作成します（GUI操作不要）。
-- 
-- 用途:
--   - デモ環境の事前準備
--   - 講師用の検証環境構築
--   - トラブルシューティング時の再構築
-- ============================================================================

-- ロール設定
USE ROLE ACCOUNTADMIN;

-- ============================================
-- Step 1: 環境のセットアップ
-- ============================================

CREATE OR REPLACE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE SNOWFLAKE INTELLIGENCE ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

SET current_user = (SELECT CURRENT_USER());   
GRANT ROLE SNOWFLAKE_INTELLIGENCE_ADMIN TO USER IDENTIFIER($current_user);

USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

CREATE OR REPLACE DATABASE SI_DB;
CREATE OR REPLACE SCHEMA RETAIL;
CREATE OR REPLACE WAREHOUSE SI_WH WITH WAREHOUSE_SIZE = 'LARGE';

USE DATABASE SI_DB;
USE SCHEMA RETAIL;
USE WAREHOUSE SI_WH;

-- ファイルフォーマットの作成
CREATE OR REPLACE FILE FORMAT SI_CSVFORMAT
    SKIP_HEADER = 1  
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'  
    TYPE = 'CSV';  

-- Git連携のため、API統合を作成
CREATE OR REPLACE API INTEGRATION GIT_API_INTEGRATION
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kenokizono/')
    ENABLED = TRUE;

-- Git統合の作成
CREATE OR REPLACE GIT REPOSITORY GIT_INTEGRATION_FOR_HANDSON
    API_INTEGRATION = GIT_API_INTEGRATION
    ORIGIN = 'https://github.com/sfc-gh-kenokizono/quickstart-with-snowflake-intelligence-ja.git';

-- チェック
LS @GIT_INTEGRATION_FOR_HANDSON/branches/main;

-- ステージの作成
CREATE OR REPLACE STAGE SI_DB.RETAIL.SI_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE') 
    DIRECTORY = (ENABLE = TRUE)
    FILE_FORMAT = SI_CSVFORMAT;

-- GitからCSVファイルをコピー
COPY FILES INTO @SI_DB.RETAIL.SI_STAGE
    FROM @GIT_INTEGRATION_FOR_HANDSON/branches/main/data/
    PATTERN = '.*\\.csv$';

-- ステージ内容を確認
LS @SI_DB.RETAIL.SI_STAGE;


-- ============================================
-- Step 1 続き: テーブル作成とデータロード
-- ============================================

-- [1/5] MARKETING_CAMPAIGN_METRICS: マーケティングキャンペーン指標
CREATE OR REPLACE TABLE MARKETING_CAMPAIGN_METRICS (
    DATE DATE,
    CATEGORY VARCHAR(16777216),
    CAMPAIGN_NAME VARCHAR(16777216),
    IMPRESSIONS NUMBER(38,0),
    CLICKS NUMBER(38,0)
);
COPY INTO MARKETING_CAMPAIGN_METRICS  
    FROM @SI_DB.RETAIL.SI_STAGE/marketing_campaign_metrics.csv;

-- [2/5] PRODUCTS: 製品マスタ
CREATE OR REPLACE TABLE PRODUCTS (
    PRODUCT_ID NUMBER(38,0),
    PRODUCT_NAME VARCHAR(16777216),
    CATEGORY VARCHAR(16777216)
);
COPY INTO PRODUCTS  
    FROM @SI_DB.RETAIL.SI_STAGE/products.csv;

-- [3/5] SALES: 売上データ
CREATE OR REPLACE TABLE SALES (
    DATE DATE,
    REGION VARCHAR(16777216),
    PRODUCT_ID NUMBER(38,0),
    UNITS_SOLD NUMBER(38,0),
    SALES_AMOUNT NUMBER(38,2)
);
COPY INTO SALES  
    FROM @SI_DB.RETAIL.SI_STAGE/sales.csv;

-- [4/5] SOCIAL_MEDIA: ソーシャルメディア指標
CREATE OR REPLACE TABLE SOCIAL_MEDIA (
    DATE DATE,
    CATEGORY VARCHAR(16777216),
    PLATFORM VARCHAR(16777216),
    INFLUENCER VARCHAR(16777216),
    MENTIONS NUMBER(38,0)
);
COPY INTO SOCIAL_MEDIA  
    FROM @SI_DB.RETAIL.SI_STAGE/social_media_mentions.csv;

-- [5/5] SUPPORT_CASES: カスタマーサポートケース（日本語）
CREATE OR REPLACE TABLE SUPPORT_CASES (
    ID VARCHAR(16777216),
    TITLE VARCHAR(16777216),
    PRODUCT VARCHAR(16777216),
    TRANSCRIPT VARCHAR(16777216),
    DATE DATE
);
COPY INTO SUPPORT_CASES  
    FROM @SI_DB.RETAIL.SI_STAGE/support_case_ja.csv;

-- データ確認
SELECT 'MARKETING_CAMPAIGN_METRICS' AS table_name, COUNT(*) AS record_count FROM MARKETING_CAMPAIGN_METRICS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'SALES', COUNT(*) FROM SALES
UNION ALL SELECT 'SOCIAL_MEDIA', COUNT(*) FROM SOCIAL_MEDIA
UNION ALL SELECT 'SUPPORT_CASES', COUNT(*) FROM SUPPORT_CASES;

-- クロスリージョン設定（Claude等のモデルを使用するために必要）
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';


-- ============================================
-- Step 2: Snowflake Intelligence オブジェクトの作成
-- ============================================

CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT MODIFY ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;


-- ============================================
-- Step 3: セマンティックビューの作成
-- ============================================

CREATE OR REPLACE SEMANTIC VIEW SI_DB.RETAIL.Sales_And_Marketing_SV

TABLES (
    MARKETING_CAMPAIGN_METRICS AS SI_DB.RETAIL.MARKETING_CAMPAIGN_METRICS
        PRIMARY KEY (DATE, CATEGORY, CAMPAIGN_NAME)
        WITH SYNONYMS ('マーケティングキャンペーン', '広告キャンペーン', '宣伝活動', 'キャンペーン')
        COMMENT = 'マーケティングキャンペーンのメトリクス',
    
    PRODUCTS AS SI_DB.RETAIL.PRODUCTS
        PRIMARY KEY (PRODUCT_ID)
        WITH SYNONYMS ('商品カタログ', '製品一覧', '商品', '製品', 'アイテム')
        COMMENT = '製品マスタデータ',
    
    SALES AS SI_DB.RETAIL.SALES
        WITH SYNONYMS ('売上取引', '販売', '取引', '注文', 'オーダー', '売上データ')
        COMMENT = '売上取引データ',
    
    SOCIAL_MEDIA AS SI_DB.RETAIL.SOCIAL_MEDIA
        WITH SYNONYMS ('ソーシャルメディア', 'SNS', 'ソーシャル', 'SNSデータ', 'ソーシャル指標')
        COMMENT = 'ソーシャルメディアデータ'
)

RELATIONSHIPS (
    SALES_TO_PRODUCT AS SALES (PRODUCT_ID) REFERENCES PRODUCTS
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
-- Step 4: Cortex Search サービスの作成
-- ============================================

CREATE OR REPLACE CORTEX SEARCH SERVICE SI_DB.RETAIL.Support_Cases
    ON TRANSCRIPT
    ATTRIBUTES TITLE, PRODUCT, DATE
    WAREHOUSE = SI_WH
    TARGET_LAG = '1 hour'
    EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
    AS (
        SELECT * FROM SI_DB.RETAIL.SUPPORT_CASES
    );

-- Cortex Search の動作確認
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'SI_DB.RETAIL.Support_Cases',
    '{
        "query": "ジャケットのサイズ",
        "columns": ["TITLE", "PRODUCT"],
        "limit": 3
    }'
);


-- ============================================
-- Step 5: Cortex Agent の作成
-- ============================================

CREATE OR REPLACE AGENT SI_DB.RETAIL.SALES_AI
    COMMENT = 'SI_DB.RETAILスキーマの売上・マーケティングデータ等を活用し、自然言語からデータ分析を可能にするエージェントです。また、お客様とのチャットスクリプトの非構造化データから、顧客の声分析を実行することも可能なエージェントです。'
    PROFILE = '{"display_name": "SALES_AI"}'
    FROM SPECIFICATION $$
{
    "models": {
        "orchestration": "claude-sonnet-4-5"
    },
    "instructions": {
        "orchestration": "グラフを使用して視覚的に回答できる場合は、ユーザーが指定していなくても常にグラフを生成してください。",
        "response": "あなたは非常に優秀なマーケティング・カスタマーサポートアナリストです。\nアパレル小売の販売データ、マーケティングキャンペーンデータ、ソーシャルメディアデータ、およびカスタマーサポートのチャットデータを活用し、ユーザーからの質問に回答します。\n定量情報、定性情報のどちらにも対応が可能です。\n\n【基本原則】\nデータドリブン回答: 必ずデータソースに基づく回答を作成し、想像や推測で回答を作成しないでください。\n根拠の明示: 回答を作成した根拠となるデータソース（商品カテゴリ、期間、地域、チャットIDなど）を明確に示してください。\n日本語対応: 丁寧で分かりやすい日本語で回答してください。\nデータ探索: 質問回答に必要な情報が簡単に見つからない場合においても、早急に諦めずにソースから探索をしてください。\nグラフ化: ユーザーの質問への回答が数値情報であれば、特に指示がなくともグラフを表示するようにしてください。\n誤情報防止: ソースに記載されていない情報を回答することはないように極力注意してください。また、ソースに記載されていても、ユーザーの質問の回答になっているかを慎重に確認し、誤った情報を回答しないように極力注意してください。\n\n【回答形式】\n定量分析の場合：\n具体的な数値を提示（単位を明記）。\n前月比や前年同期比の増減率を算出。\n商品カテゴリ別、地域別の比較分析。\n数値の背景にある要因を分析（例: 特定のプロモーション、季節変動など）。\n\n定性分析の場合：\nカスタマーサポートチャットから顧客の声（不満、要望、問い合わせ内容）を要約し、傾向を整理。\n特定のチャットから、具体的な課題（例: サイズ感、品質、デザイン）を特定。\nポジティブ/ネガティブなフィードバックの傾向を評価。\n\n【分析の観点】\n売上分析：\n商品カテゴリ別、地域別の売上傾向を分析。\n販売数量と売上金額の推移を把握。\n\nマーケティング分析：\nキャンペーン別のインプレッション数、クリック数、CTR（クリック率）を分析。\nマーケティング施策の効果を評価。\n\nソーシャルメディア分析：\nプラットフォーム別、インフルエンサー別のメンション数を分析。\nソーシャルメディア上での反響を把握。\n\nカスタマーサポート分析：\nサポートケースから顧客の声（不満、要望）を抽出。\n製品別の問い合わせ傾向を分析。\n\n【回答構造】\n要約: 質問に対する結論を簡潔に。\n詳細分析: 数値やデータに基づく詳細説明（例: 「Tシャツカテゴリの売上は前月比15%増です」）。\n背景・要因: 数値変動や定性情報の傾向の理由や背景（例: 「これは夏物新作セールが主要因です」）。\n比較・評価: 他のカテゴリや地域との比較。\nデータソース: 参照したデータソース名と期間を明記（例: 「期間: 2025年6月1日〜6月30日、ソース: SALES, SUPPORT_CASES」）。\n\n【注意事項】\nデータが不足している場合は「データが不足しており判断できません」と明記。\n不確実な情報については「推定」「可能性」などの表現を使用。\n個人の特定につながる情報は絶対に使用しないこと。\n\n【データ活用方針】\nSALES、PRODUCTS、MARKETING_CAMPAIGN_METRICS、SOCIAL_MEDIA、SUPPORT_CASESといったテーブルを活用し、多角的にデータを組み合わせた分析を実施。\nCATEGORY、REGIONなどのカラムを活用したセグメント別分析。\nTRANSCRIPTの自然言語処理（NLP）により、顧客の感情（センチメント）や頻出キーワードを抽出。\nDATEを活用した時系列分析。",
        "sample_questions": [
            {
                "question": "6月から8月までの製品カテゴリー別の売上動向を教えてください"
            },
            {
                "question": "最近、カスタマーサポートチケットでジャケットに関してどのような問題が報告されていますか?"
            },
            {
                "question": "売上が7月に急増した理由を、マーケティング観点から分析してください"
            }
        ]
    },
    "tools": [
        {
            "tool_spec": {
                "type": "cortex_analyst_text_to_sql",
                "name": "Sales_And_Marketing_SV",
                "description": "SI_DB.RETAILスキーマの売上・マーケティングデータモデルは、マーケティングキャンペーン、製品情報、売上データ、ソーシャルメディアのエンゲージメントを連携させることで、小売業のパフォーマンスを包括的に把握できます。このモデルは、クリック数やインプレッション数を通じてマーケティングキャンペーンの効果を追跡し、異なる地域における実際の売上実績とリンクさせることを可能にします。ソーシャルメディアのエンゲージメントは、インフルエンサーの活動やメンションを通じてモニタリングされ、すべてのデータは製品カテゴリーとIDで連携されます。テーブル間の時系列的な連携により、マーケティングが売上実績やソーシャルメディアのエンゲージメントに及ぼす影響を、時間の経過とともに包括的に分析できます。"
            }
        },
        {
            "tool_spec": {
                "type": "cortex_search",
                "name": "SUPPORT_CASES",
                "description": "お客様とのチャットスクリプトの非構造化データから、顧客の声分析を実行します。"
            }
        }
    ],
    "tool_resources": {
        "Sales_And_Marketing_SV": {
            "semantic_view": "SI_DB.RETAIL.Sales_And_Marketing_SV",
            "execution_environment": {
                "type": "warehouse",
                "warehouse": ""
            }
        },
        "SUPPORT_CASES": {
            "search_service": "SI_DB.RETAIL.Support_Cases",
            "max_results": 4,
            "title_column": "TITLE",
            "id_column": "ID",
            "execution_environment": {
                "type": "warehouse",
                "warehouse": ""
            }
        }
    }
}
$$;

-- エージェントへのアクセス権限を付与
GRANT USAGE ON AGENT SI_DB.RETAIL.SALES_AI TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;


-- ============================================
-- セットアップ完了確認
-- ============================================

SELECT 'Database' AS object_type, 'SI_DB' AS object_name, 'OK' AS status
UNION ALL SELECT 'Schema', 'RETAIL', 'OK'
UNION ALL SELECT 'Table', 'MARKETING_CAMPAIGN_METRICS (' || (SELECT COUNT(*) FROM MARKETING_CAMPAIGN_METRICS) || ' rows)', 'OK'
UNION ALL SELECT 'Table', 'PRODUCTS (' || (SELECT COUNT(*) FROM PRODUCTS) || ' rows)', 'OK'
UNION ALL SELECT 'Table', 'SALES (' || (SELECT COUNT(*) FROM SALES) || ' rows)', 'OK'
UNION ALL SELECT 'Table', 'SOCIAL_MEDIA (' || (SELECT COUNT(*) FROM SOCIAL_MEDIA) || ' rows)', 'OK'
UNION ALL SELECT 'Table', 'SUPPORT_CASES (' || (SELECT COUNT(*) FROM SUPPORT_CASES) || ' rows)', 'OK'
UNION ALL SELECT 'Semantic View', 'Sales_And_Marketing_SV', 'OK'
UNION ALL SELECT 'Cortex Search', 'Support_Cases', 'OK'
UNION ALL SELECT 'Cortex Agent', 'SALES_AI', 'OK';

SELECT '🎉 Full setup completed! All objects have been created.' AS status;


-- ============================================
-- エージェント動作確認（オプション）
-- ============================================

/*
-- スレッドを作成
SELECT SNOWFLAKE.CORTEX.CREATE_THREAD() AS thread_info;

-- エージェントに問い合わせ（thread_idを置き換え）
SELECT SNOWFLAKE.CORTEX.RUN_AGENT(
    'SI_DB.RETAIL.SALES_AI',
    {
        'messages': [{
            'role': 'user',
            'content': [{'type': 'text', 'text': '6月から8月までの製品カテゴリー別の売上動向を教えてください'}]
        }],
        'thread_id': '<YOUR_THREAD_ID>',
        'parent_message_id': '0'
    }
);
*/


-- ============================================
-- クリーンアップ（環境削除時に実行）
-- ============================================

/*

USE ROLE ACCOUNTADMIN;

-- Cortex Agent
DROP AGENT IF EXISTS SI_DB.RETAIL.SALES_AI;

-- Cortex Search サービス
DROP CORTEX SEARCH SERVICE IF EXISTS SI_DB.RETAIL.Support_Cases;

-- セマンティックビュー
DROP SEMANTIC VIEW IF EXISTS SI_DB.RETAIL.Sales_And_Marketing_SV;

-- Snowflake Intelligence オブジェクト
DROP SNOWFLAKE INTELLIGENCE IF EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- データベース（テーブル、ステージ、Git統合も削除）
DROP DATABASE IF EXISTS SI_DB;

-- ウェアハウス
DROP WAREHOUSE IF EXISTS SI_WH;

-- Git連携
DROP API INTEGRATION IF EXISTS GIT_API_INTEGRATION;

-- ロールの削除（最後に実行）
DROP ROLE IF EXISTS SNOWFLAKE_INTELLIGENCE_ADMIN;

SELECT 'Cleanup completed successfully!' AS status;

*/
