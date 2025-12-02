# Step 4: Cortex Search サービスの作成

## 目的

サポートケースのトランスクリプト（TRANSCRIPT）をセマンティック検索できるようにします。

## UIナビゲーション

```
Snowsight → AIとML → Cortex検索
 → データベース: DASH_DB_SI、スキーマ: RETAIL を選択
 → 作成
```

---

## 設定値

| 項目 | 値 |
|------|-----|
| サービスデータベースとスキーマ | `DASH_DB_SI.RETAIL` |
| サービス名 | `Support_Cases` |
| インデックスを作成するデータを選択 | `DASH_DB_SI.RETAIL.SUPPORT_CASES` |
| 検索列 | `TRANSCRIPT` |
| 属性列 | `TITLE`, `PRODUCT`, `DATE` |
| サービスに含む列を選択 | Select all |
| ターゲットラグ | 1 時間 |
| 埋め込みモデル | `snowflake-arctic-embed-l-v2.0` |
| インデックス作成用のウェアハウス | `DASH_WH_SI` |

