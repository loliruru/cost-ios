// Generated storage records. Domain and Feature must not depend on these GRDB types.
import GRDB

struct CurrencyRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "currencies"
    var code: String
    var asset_type: String
    var display_name: String
    var symbol: String
    var default_scale: Int64
    var is_enabled: Int64
    var sort_order: Int64
    var metadata_version: Int64
}

struct CategoryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "categories"
    var id: String
    var name: String
    var transaction_type: String
    var parent_id: String?
    var icon_key: String
    var color_key: String
    var icon_source: String
    var emoji: String?
    var icon_asset_id: String?
    var background_asset_id: String?
    var background_focus: String
    var sort_order: Int64
    var is_archived: Int64
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
}

struct AccountRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "accounts"
    var id: String
    var name: String
    var currency_code: String?
    var icon_key: String
    var color_key: String
    var icon_source: String
    var emoji: String?
    var icon_asset_id: String?
    var background_asset_id: String?
    var background_focus: String
    var sort_order: Int64
    var is_default: Int64
    var is_archived: Int64
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
}

struct TagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tags"
    var id: String
    var name: String
    var normalized_name: String
    var color_key: String
    var is_archived: Int64
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
}

struct TransactionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transactions"
    var id: String
    var transaction_type: String
    var original_amount_minor: Int64
    var original_scale: Int64
    var original_currency_code: String
    var base_currency_code: String
    var base_scale: Int64
    var exchange_rate_text: String
    var converted_base_amount_minor: Int64
    var rate_data_timestamp: Int64?
    var rate_fetched_at: Int64?
    var rate_provider: String
    var valuation_method: String
    var category_id: String
    var account_id: String
    var occurred_at_epoch_millis: Int64
    var occurred_zone_id: String
    var occurred_local_epoch_day: Int64
    var note: String?
    var source_type: String
    var source_id: String?
    var request_key: String?
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
    var deleted_at_epoch_millis: Int64?
    var crypto_price_text: String?
    var crypto_price_kind: String?
    var crypto_price_source: String?
    var crypto_venue: String?
    var crypto_pair: String?
    var crypto_data_timestamp: Int64?
    var crypto_fetched_at: Int64?
}

struct TransactionTagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transaction_tags"
    var transaction_id: String
    var tag_id: String
}

struct VisualAssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "visual_assets"
    var id: String
    var asset_kind: String
    var relative_path: String
    var mime_type: String
    var width_px: Int64
    var height_px: Int64
    var byte_size: Int64
    var content_sha256: String
    var processing_version: Int64
    var created_at_epoch_millis: Int64
}

struct FiatQuoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "fx_quotes"
    var id: String
    var original_currency_code: String
    var base_currency_code: String
    var rate_text: String
    var provider_id: String
    var rate_data_timestamp: Int64
    var rate_date_epoch_day: Int64?
    var fetched_at: Int64
    var expires_at: Int64
    var quote_kind: String
}

struct QuickTemplateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "quick_templates"
    var id: String
    var name: String
    var icon_key: String
    var transaction_type: String
    var amount_minor: Int64
    var amount_scale: Int64
    var currency_code: String
    var category_id: String
    var account_id: String
    var note: String?
    var sort_order: Int64
    var usage_count: Int64
    var last_used_at: Int64?
    var is_archived: Int64
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
}

struct QuickTemplateTagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "quick_template_tags"
    var template_id: String
    var tag_id: String
}

struct RecurringRuleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recurring_rules"
    var id: String
    var name: String
    var is_enabled: Int64
    var start_local_epoch_day: Int64
    var end_local_epoch_day: Int64?
    var scheduled_local_time_minutes: Int64
    var zone_id: String
    var next_occurrence_at: Int64?
    var last_evaluated_at: Int64?
    var rule_version: Int64
    var catch_up_policy: String
    var frequency: String
    var interval_value: Int64
    var interval_unit: String?
    var weekdays_mask: Int64
    var day_of_month: Int64?
    var month_of_year: Int64?
    var month_day_policy: String
    var transaction_type: String
    var amount_minor: Int64
    var amount_scale: Int64
    var currency_code: String
    var category_id: String
    var account_id: String
    var note: String?
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
}

struct RecurringRuleTagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recurring_rule_tags"
    var rule_id: String
    var tag_id: String
}

struct RecurringExecutionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recurring_executions"
    var id: String
    var rule_id: String
    var scheduled_at: Int64
    var status: String
    var transaction_id: String?
    var attempt_count: Int64
    var last_error: String?
    var created_at_epoch_millis: Int64
    var updated_at_epoch_millis: Int64
}

struct MarketQuoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "crypto_price_quotes"
    var asset_code: String
    var base_code: String
    var provider_id: String
    var price_text: String
    var venue: String
    var data_timestamp: Int64
    var fetched_at: Int64
    var expires_at: Int64
}

struct AnomalyFeedbackRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "anomaly_feedback"
    var id: String
    var feedback_type: String
    var kind: String
    var category_id: String?
    var base_currency_code: String
    var amount_minor_text: String
    var base_scale: Int64
    var feature_version: Int64
    var created_at_epoch_millis: Int64
}

struct RestoreStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "restore_state"
    var id: Int64
    var settings: String
}

struct AccountFundOpeningRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "account_fund_openings"
    var id: String
    var account_id: String
    var revision: Int64
    var kind: String
    var enabled: Int64
    var currency_code: String
    var scale: Int64
    var amount_minor: Int64?
    var started_at: Int64
    var created_at: Int64
}

struct AccountTransferRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "account_transfers"
    var id: String
    var request_key: String
    var from_account_id: String
    var to_account_id: String
    var from_kind: String
    var to_kind: String
    var currency_code: String
    var scale: Int64
    var principal_minor: Int64
    var profit_minor: Int64
    var profit_category_id: String?
    var profit_transaction_id: String?
    var occurred_at: Int64
    var zone_id: String
    var note: String?
    var created_at: Int64
    var updated_at: Int64
    var deleted_at: Int64?
}
