-- Frozen iOS v1 schema, adapted from Android Room v10 definitions and runtime invariants.

-- Android CostDatabase.kt SHA-256: 4a9f0198732c011ad74059d8ff369e800631ee441e8a56799f1388510eb551e1

CREATE TABLE IF NOT EXISTS `currencies` (`code` TEXT NOT NULL, `asset_type` TEXT NOT NULL, `display_name` TEXT NOT NULL, `symbol` TEXT NOT NULL, `default_scale` INTEGER NOT NULL, `is_enabled` INTEGER NOT NULL, `sort_order` INTEGER NOT NULL, `metadata_version` INTEGER NOT NULL, PRIMARY KEY(`code`));

CREATE TRIGGER currencies_types_insert BEFORE INSERT ON currencies
WHEN (typeof(NEW.code) IN ('text') AND typeof(NEW.asset_type) IN ('text') AND typeof(NEW.display_name) IN ('text') AND typeof(NEW.symbol) IN ('text') AND typeof(NEW.default_scale) IN ('integer') AND typeof(NEW.is_enabled) IN ('integer') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.metadata_version) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER currencies_types_update BEFORE UPDATE ON currencies
WHEN (typeof(NEW.code) IN ('text') AND typeof(NEW.asset_type) IN ('text') AND typeof(NEW.display_name) IN ('text') AND typeof(NEW.symbol) IN ('text') AND typeof(NEW.default_scale) IN ('integer') AND typeof(NEW.is_enabled) IN ('integer') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.metadata_version) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `categories` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `transaction_type` TEXT NOT NULL, `parent_id` TEXT, `icon_key` TEXT NOT NULL, `color_key` TEXT NOT NULL, `icon_source` TEXT NOT NULL DEFAULT 'BUILT_IN', `emoji` TEXT, `icon_asset_id` TEXT, `background_asset_id` TEXT, `background_focus` TEXT NOT NULL DEFAULT 'CENTER', `sort_order` INTEGER NOT NULL, `is_archived` INTEGER NOT NULL, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`parent_id`) REFERENCES `categories`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`icon_asset_id`) REFERENCES `visual_assets`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`background_asset_id`) REFERENCES `visual_assets`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_categories_parent_id` ON `categories` (`parent_id`);

CREATE INDEX IF NOT EXISTS `index_categories_icon_asset_id` ON `categories` (`icon_asset_id`);

CREATE INDEX IF NOT EXISTS `index_categories_background_asset_id` ON `categories` (`background_asset_id`);

CREATE TRIGGER categories_types_insert BEFORE INSERT ON categories
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.parent_id) IN ('text', 'null') AND typeof(NEW.icon_key) IN ('text') AND typeof(NEW.color_key) IN ('text') AND typeof(NEW.icon_source) IN ('text') AND typeof(NEW.emoji) IN ('text', 'null') AND typeof(NEW.icon_asset_id) IN ('text', 'null') AND typeof(NEW.background_asset_id) IN ('text', 'null') AND typeof(NEW.background_focus) IN ('text') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER categories_types_update BEFORE UPDATE ON categories
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.parent_id) IN ('text', 'null') AND typeof(NEW.icon_key) IN ('text') AND typeof(NEW.color_key) IN ('text') AND typeof(NEW.icon_source) IN ('text') AND typeof(NEW.emoji) IN ('text', 'null') AND typeof(NEW.icon_asset_id) IN ('text', 'null') AND typeof(NEW.background_asset_id) IN ('text', 'null') AND typeof(NEW.background_focus) IN ('text') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `accounts` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `currency_code` TEXT, `icon_key` TEXT NOT NULL, `color_key` TEXT NOT NULL, `icon_source` TEXT NOT NULL DEFAULT 'BUILT_IN', `emoji` TEXT, `icon_asset_id` TEXT, `background_asset_id` TEXT, `background_focus` TEXT NOT NULL DEFAULT 'CENTER', `sort_order` INTEGER NOT NULL, `is_default` INTEGER NOT NULL, `is_archived` INTEGER NOT NULL, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`icon_asset_id`) REFERENCES `visual_assets`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`background_asset_id`) REFERENCES `visual_assets`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_accounts_currency_code` ON `accounts` (`currency_code`);

CREATE INDEX IF NOT EXISTS `index_accounts_icon_asset_id` ON `accounts` (`icon_asset_id`);

CREATE INDEX IF NOT EXISTS `index_accounts_background_asset_id` ON `accounts` (`background_asset_id`);

CREATE TRIGGER accounts_types_insert BEFORE INSERT ON accounts
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.currency_code) IN ('text', 'null') AND typeof(NEW.icon_key) IN ('text') AND typeof(NEW.color_key) IN ('text') AND typeof(NEW.icon_source) IN ('text') AND typeof(NEW.emoji) IN ('text', 'null') AND typeof(NEW.icon_asset_id) IN ('text', 'null') AND typeof(NEW.background_asset_id) IN ('text', 'null') AND typeof(NEW.background_focus) IN ('text') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.is_default) IN ('integer') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER accounts_types_update BEFORE UPDATE ON accounts
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.currency_code) IN ('text', 'null') AND typeof(NEW.icon_key) IN ('text') AND typeof(NEW.color_key) IN ('text') AND typeof(NEW.icon_source) IN ('text') AND typeof(NEW.emoji) IN ('text', 'null') AND typeof(NEW.icon_asset_id) IN ('text', 'null') AND typeof(NEW.background_asset_id) IN ('text', 'null') AND typeof(NEW.background_focus) IN ('text') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.is_default) IN ('integer') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `tags` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `normalized_name` TEXT NOT NULL, `color_key` TEXT NOT NULL, `is_archived` INTEGER NOT NULL, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`));

CREATE UNIQUE INDEX IF NOT EXISTS `index_tags_normalized_name` ON `tags` (`normalized_name`);

CREATE TRIGGER tags_types_insert BEFORE INSERT ON tags
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.normalized_name) IN ('text') AND typeof(NEW.color_key) IN ('text') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER tags_types_update BEFORE UPDATE ON tags
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.normalized_name) IN ('text') AND typeof(NEW.color_key) IN ('text') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `transactions` (`id` TEXT NOT NULL, `transaction_type` TEXT NOT NULL, `original_amount_minor` INTEGER NOT NULL, `original_scale` INTEGER NOT NULL, `original_currency_code` TEXT NOT NULL, `base_currency_code` TEXT NOT NULL, `base_scale` INTEGER NOT NULL, `exchange_rate_text` TEXT NOT NULL, `converted_base_amount_minor` INTEGER NOT NULL, `rate_data_timestamp` INTEGER, `rate_fetched_at` INTEGER, `rate_provider` TEXT NOT NULL, `valuation_method` TEXT NOT NULL, `category_id` TEXT NOT NULL, `account_id` TEXT NOT NULL, `occurred_at_epoch_millis` INTEGER NOT NULL, `occurred_zone_id` TEXT NOT NULL, `occurred_local_epoch_day` INTEGER NOT NULL, `note` TEXT, `source_type` TEXT NOT NULL, `source_id` TEXT, `request_key` TEXT, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, `deleted_at_epoch_millis` INTEGER, `crypto_price_text` TEXT, `crypto_price_kind` TEXT, `crypto_price_source` TEXT, `crypto_venue` TEXT, `crypto_pair` TEXT, `crypto_data_timestamp` INTEGER, `crypto_fetched_at` INTEGER, PRIMARY KEY(`id`), FOREIGN KEY(`original_currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`base_currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`category_id`) REFERENCES `categories`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`account_id`) REFERENCES `accounts`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_transactions_recent` ON `transactions` (`occurred_at_epoch_millis`, `id`);

CREATE INDEX IF NOT EXISTS `index_transactions_day_type` ON `transactions` (`occurred_local_epoch_day`, `transaction_type`);

CREATE INDEX IF NOT EXISTS `index_transactions_category_day` ON `transactions` (`category_id`, `occurred_local_epoch_day`);

CREATE INDEX IF NOT EXISTS `index_transactions_account_day` ON `transactions` (`account_id`, `occurred_local_epoch_day`);

CREATE INDEX IF NOT EXISTS `index_transactions_base_currency_day` ON `transactions` (`base_currency_code`, `occurred_local_epoch_day`);

CREATE INDEX IF NOT EXISTS `index_transactions_original_currency` ON `transactions` (`original_currency_code`);

CREATE INDEX IF NOT EXISTS `index_transactions_source` ON `transactions` (`source_type`, `source_id`);

CREATE UNIQUE INDEX IF NOT EXISTS `index_transactions_request_key` ON `transactions` (`request_key`);

CREATE TRIGGER transactions_types_insert BEFORE INSERT ON transactions
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.original_amount_minor) IN ('integer') AND typeof(NEW.original_scale) IN ('integer') AND typeof(NEW.original_currency_code) IN ('text') AND typeof(NEW.base_currency_code) IN ('text') AND typeof(NEW.base_scale) IN ('integer') AND typeof(NEW.exchange_rate_text) IN ('text') AND typeof(NEW.converted_base_amount_minor) IN ('integer') AND typeof(NEW.rate_data_timestamp) IN ('integer', 'null') AND typeof(NEW.rate_fetched_at) IN ('integer', 'null') AND typeof(NEW.rate_provider) IN ('text') AND typeof(NEW.valuation_method) IN ('text') AND typeof(NEW.category_id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.occurred_at_epoch_millis) IN ('integer') AND typeof(NEW.occurred_zone_id) IN ('text') AND typeof(NEW.occurred_local_epoch_day) IN ('integer') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.source_type) IN ('text') AND typeof(NEW.source_id) IN ('text', 'null') AND typeof(NEW.request_key) IN ('text', 'null') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer') AND typeof(NEW.deleted_at_epoch_millis) IN ('integer', 'null') AND typeof(NEW.crypto_price_text) IN ('text', 'null') AND typeof(NEW.crypto_price_kind) IN ('text', 'null') AND typeof(NEW.crypto_price_source) IN ('text', 'null') AND typeof(NEW.crypto_venue) IN ('text', 'null') AND typeof(NEW.crypto_pair) IN ('text', 'null') AND typeof(NEW.crypto_data_timestamp) IN ('integer', 'null') AND typeof(NEW.crypto_fetched_at) IN ('integer', 'null')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER transactions_types_update BEFORE UPDATE ON transactions
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.original_amount_minor) IN ('integer') AND typeof(NEW.original_scale) IN ('integer') AND typeof(NEW.original_currency_code) IN ('text') AND typeof(NEW.base_currency_code) IN ('text') AND typeof(NEW.base_scale) IN ('integer') AND typeof(NEW.exchange_rate_text) IN ('text') AND typeof(NEW.converted_base_amount_minor) IN ('integer') AND typeof(NEW.rate_data_timestamp) IN ('integer', 'null') AND typeof(NEW.rate_fetched_at) IN ('integer', 'null') AND typeof(NEW.rate_provider) IN ('text') AND typeof(NEW.valuation_method) IN ('text') AND typeof(NEW.category_id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.occurred_at_epoch_millis) IN ('integer') AND typeof(NEW.occurred_zone_id) IN ('text') AND typeof(NEW.occurred_local_epoch_day) IN ('integer') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.source_type) IN ('text') AND typeof(NEW.source_id) IN ('text', 'null') AND typeof(NEW.request_key) IN ('text', 'null') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer') AND typeof(NEW.deleted_at_epoch_millis) IN ('integer', 'null') AND typeof(NEW.crypto_price_text) IN ('text', 'null') AND typeof(NEW.crypto_price_kind) IN ('text', 'null') AND typeof(NEW.crypto_price_source) IN ('text', 'null') AND typeof(NEW.crypto_venue) IN ('text', 'null') AND typeof(NEW.crypto_pair) IN ('text', 'null') AND typeof(NEW.crypto_data_timestamp) IN ('integer', 'null') AND typeof(NEW.crypto_fetched_at) IN ('integer', 'null')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `transaction_tags` (`transaction_id` TEXT NOT NULL, `tag_id` TEXT NOT NULL, PRIMARY KEY(`transaction_id`, `tag_id`), FOREIGN KEY(`transaction_id`) REFERENCES `transactions`(`id`) ON UPDATE CASCADE ON DELETE CASCADE , FOREIGN KEY(`tag_id`) REFERENCES `tags`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_transaction_tags_tag_id` ON `transaction_tags` (`tag_id`);

CREATE TRIGGER transaction_tags_types_insert BEFORE INSERT ON transaction_tags
WHEN (typeof(NEW.transaction_id) IN ('text') AND typeof(NEW.tag_id) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER transaction_tags_types_update BEFORE UPDATE ON transaction_tags
WHEN (typeof(NEW.transaction_id) IN ('text') AND typeof(NEW.tag_id) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `visual_assets` (`id` TEXT NOT NULL, `asset_kind` TEXT NOT NULL, `relative_path` TEXT NOT NULL, `mime_type` TEXT NOT NULL, `width_px` INTEGER NOT NULL, `height_px` INTEGER NOT NULL, `byte_size` INTEGER NOT NULL, `content_sha256` TEXT NOT NULL, `processing_version` INTEGER NOT NULL, `created_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`));

CREATE UNIQUE INDEX IF NOT EXISTS `index_visual_assets_relative_path` ON `visual_assets` (`relative_path`);

CREATE UNIQUE INDEX IF NOT EXISTS `index_visual_assets_deduplication` ON `visual_assets` (`asset_kind`, `content_sha256`, `processing_version`);

CREATE TRIGGER visual_assets_types_insert BEFORE INSERT ON visual_assets
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.asset_kind) IN ('text') AND typeof(NEW.relative_path) IN ('text') AND typeof(NEW.mime_type) IN ('text') AND typeof(NEW.width_px) IN ('integer') AND typeof(NEW.height_px) IN ('integer') AND typeof(NEW.byte_size) IN ('integer') AND typeof(NEW.content_sha256) IN ('text') AND typeof(NEW.processing_version) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER visual_assets_types_update BEFORE UPDATE ON visual_assets
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.asset_kind) IN ('text') AND typeof(NEW.relative_path) IN ('text') AND typeof(NEW.mime_type) IN ('text') AND typeof(NEW.width_px) IN ('integer') AND typeof(NEW.height_px) IN ('integer') AND typeof(NEW.byte_size) IN ('integer') AND typeof(NEW.content_sha256) IN ('text') AND typeof(NEW.processing_version) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `fx_quotes` (`id` TEXT NOT NULL, `original_currency_code` TEXT NOT NULL, `base_currency_code` TEXT NOT NULL, `rate_text` TEXT NOT NULL, `provider_id` TEXT NOT NULL, `rate_data_timestamp` INTEGER NOT NULL, `rate_date_epoch_day` INTEGER, `fetched_at` INTEGER NOT NULL, `expires_at` INTEGER NOT NULL, `quote_kind` TEXT NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`original_currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE CASCADE , FOREIGN KEY(`base_currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE CASCADE );

CREATE INDEX IF NOT EXISTS `index_fx_quotes_original_currency` ON `fx_quotes` (`original_currency_code`);

CREATE INDEX IF NOT EXISTS `index_fx_quotes_base_currency` ON `fx_quotes` (`base_currency_code`);

CREATE UNIQUE INDEX IF NOT EXISTS `index_fx_quotes_provider_pair_kind_timestamp` ON `fx_quotes` (`provider_id`, `original_currency_code`, `base_currency_code`, `quote_kind`, `rate_data_timestamp`);

CREATE INDEX IF NOT EXISTS `index_fx_quotes_provider_pair_kind_date` ON `fx_quotes` (`provider_id`, `original_currency_code`, `base_currency_code`, `quote_kind`, `rate_date_epoch_day`);

CREATE INDEX IF NOT EXISTS `index_fx_quotes_expires_at` ON `fx_quotes` (`expires_at`);

CREATE TRIGGER fx_quotes_types_insert BEFORE INSERT ON fx_quotes
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.original_currency_code) IN ('text') AND typeof(NEW.base_currency_code) IN ('text') AND typeof(NEW.rate_text) IN ('text') AND typeof(NEW.provider_id) IN ('text') AND typeof(NEW.rate_data_timestamp) IN ('integer') AND typeof(NEW.rate_date_epoch_day) IN ('integer', 'null') AND typeof(NEW.fetched_at) IN ('integer') AND typeof(NEW.expires_at) IN ('integer') AND typeof(NEW.quote_kind) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER fx_quotes_types_update BEFORE UPDATE ON fx_quotes
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.original_currency_code) IN ('text') AND typeof(NEW.base_currency_code) IN ('text') AND typeof(NEW.rate_text) IN ('text') AND typeof(NEW.provider_id) IN ('text') AND typeof(NEW.rate_data_timestamp) IN ('integer') AND typeof(NEW.rate_date_epoch_day) IN ('integer', 'null') AND typeof(NEW.fetched_at) IN ('integer') AND typeof(NEW.expires_at) IN ('integer') AND typeof(NEW.quote_kind) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `quick_templates` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `icon_key` TEXT NOT NULL, `transaction_type` TEXT NOT NULL, `amount_minor` INTEGER NOT NULL, `amount_scale` INTEGER NOT NULL, `currency_code` TEXT NOT NULL, `category_id` TEXT NOT NULL, `account_id` TEXT NOT NULL, `note` TEXT, `sort_order` INTEGER NOT NULL, `usage_count` INTEGER NOT NULL, `last_used_at` INTEGER, `is_archived` INTEGER NOT NULL, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`category_id`) REFERENCES `categories`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`account_id`) REFERENCES `accounts`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_quick_templates_sort_order` ON `quick_templates` (`sort_order`);

CREATE INDEX IF NOT EXISTS `index_quick_templates_last_used_at` ON `quick_templates` (`last_used_at`);

CREATE INDEX IF NOT EXISTS `index_quick_templates_currency` ON `quick_templates` (`currency_code`);

CREATE INDEX IF NOT EXISTS `index_quick_templates_category` ON `quick_templates` (`category_id`);

CREATE INDEX IF NOT EXISTS `index_quick_templates_account` ON `quick_templates` (`account_id`);

CREATE TRIGGER quick_templates_types_insert BEFORE INSERT ON quick_templates
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.icon_key) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.amount_minor) IN ('integer') AND typeof(NEW.amount_scale) IN ('integer') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.category_id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.usage_count) IN ('integer') AND typeof(NEW.last_used_at) IN ('integer', 'null') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER quick_templates_types_update BEFORE UPDATE ON quick_templates
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.icon_key) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.amount_minor) IN ('integer') AND typeof(NEW.amount_scale) IN ('integer') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.category_id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.sort_order) IN ('integer') AND typeof(NEW.usage_count) IN ('integer') AND typeof(NEW.last_used_at) IN ('integer', 'null') AND typeof(NEW.is_archived) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `quick_template_tags` (`template_id` TEXT NOT NULL, `tag_id` TEXT NOT NULL, PRIMARY KEY(`template_id`, `tag_id`), FOREIGN KEY(`template_id`) REFERENCES `quick_templates`(`id`) ON UPDATE CASCADE ON DELETE CASCADE , FOREIGN KEY(`tag_id`) REFERENCES `tags`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_quick_template_tags_tag_id` ON `quick_template_tags` (`tag_id`);

CREATE TRIGGER quick_template_tags_types_insert BEFORE INSERT ON quick_template_tags
WHEN (typeof(NEW.template_id) IN ('text') AND typeof(NEW.tag_id) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER quick_template_tags_types_update BEFORE UPDATE ON quick_template_tags
WHEN (typeof(NEW.template_id) IN ('text') AND typeof(NEW.tag_id) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `recurring_rules` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `is_enabled` INTEGER NOT NULL, `start_local_epoch_day` INTEGER NOT NULL, `end_local_epoch_day` INTEGER, `scheduled_local_time_minutes` INTEGER NOT NULL, `zone_id` TEXT NOT NULL, `next_occurrence_at` INTEGER, `last_evaluated_at` INTEGER, `rule_version` INTEGER NOT NULL, `catch_up_policy` TEXT NOT NULL, `frequency` TEXT NOT NULL, `interval_value` INTEGER NOT NULL, `interval_unit` TEXT, `weekdays_mask` INTEGER NOT NULL, `day_of_month` INTEGER, `month_of_year` INTEGER, `month_day_policy` TEXT NOT NULL, `transaction_type` TEXT NOT NULL, `amount_minor` INTEGER NOT NULL, `amount_scale` INTEGER NOT NULL, `currency_code` TEXT NOT NULL, `category_id` TEXT NOT NULL, `account_id` TEXT NOT NULL, `note` TEXT, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`currency_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`category_id`) REFERENCES `categories`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT , FOREIGN KEY(`account_id`) REFERENCES `accounts`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_recurring_rules_due` ON `recurring_rules` (`is_enabled`, `next_occurrence_at`);

CREATE INDEX IF NOT EXISTS `index_recurring_rules_currency` ON `recurring_rules` (`currency_code`);

CREATE INDEX IF NOT EXISTS `index_recurring_rules_category` ON `recurring_rules` (`category_id`);

CREATE INDEX IF NOT EXISTS `index_recurring_rules_account` ON `recurring_rules` (`account_id`);

CREATE TRIGGER recurring_rules_types_insert BEFORE INSERT ON recurring_rules
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.is_enabled) IN ('integer') AND typeof(NEW.start_local_epoch_day) IN ('integer') AND typeof(NEW.end_local_epoch_day) IN ('integer', 'null') AND typeof(NEW.scheduled_local_time_minutes) IN ('integer') AND typeof(NEW.zone_id) IN ('text') AND typeof(NEW.next_occurrence_at) IN ('integer', 'null') AND typeof(NEW.last_evaluated_at) IN ('integer', 'null') AND typeof(NEW.rule_version) IN ('integer') AND typeof(NEW.catch_up_policy) IN ('text') AND typeof(NEW.frequency) IN ('text') AND typeof(NEW.interval_value) IN ('integer') AND typeof(NEW.interval_unit) IN ('text', 'null') AND typeof(NEW.weekdays_mask) IN ('integer') AND typeof(NEW.day_of_month) IN ('integer', 'null') AND typeof(NEW.month_of_year) IN ('integer', 'null') AND typeof(NEW.month_day_policy) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.amount_minor) IN ('integer') AND typeof(NEW.amount_scale) IN ('integer') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.category_id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER recurring_rules_types_update BEFORE UPDATE ON recurring_rules
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.name) IN ('text') AND typeof(NEW.is_enabled) IN ('integer') AND typeof(NEW.start_local_epoch_day) IN ('integer') AND typeof(NEW.end_local_epoch_day) IN ('integer', 'null') AND typeof(NEW.scheduled_local_time_minutes) IN ('integer') AND typeof(NEW.zone_id) IN ('text') AND typeof(NEW.next_occurrence_at) IN ('integer', 'null') AND typeof(NEW.last_evaluated_at) IN ('integer', 'null') AND typeof(NEW.rule_version) IN ('integer') AND typeof(NEW.catch_up_policy) IN ('text') AND typeof(NEW.frequency) IN ('text') AND typeof(NEW.interval_value) IN ('integer') AND typeof(NEW.interval_unit) IN ('text', 'null') AND typeof(NEW.weekdays_mask) IN ('integer') AND typeof(NEW.day_of_month) IN ('integer', 'null') AND typeof(NEW.month_of_year) IN ('integer', 'null') AND typeof(NEW.month_day_policy) IN ('text') AND typeof(NEW.transaction_type) IN ('text') AND typeof(NEW.amount_minor) IN ('integer') AND typeof(NEW.amount_scale) IN ('integer') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.category_id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `recurring_rule_tags` (`rule_id` TEXT NOT NULL, `tag_id` TEXT NOT NULL, PRIMARY KEY(`rule_id`, `tag_id`), FOREIGN KEY(`rule_id`) REFERENCES `recurring_rules`(`id`) ON UPDATE CASCADE ON DELETE CASCADE , FOREIGN KEY(`tag_id`) REFERENCES `tags`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE INDEX IF NOT EXISTS `index_recurring_rule_tags_tag_id` ON `recurring_rule_tags` (`tag_id`);

CREATE TRIGGER recurring_rule_tags_types_insert BEFORE INSERT ON recurring_rule_tags
WHEN (typeof(NEW.rule_id) IN ('text') AND typeof(NEW.tag_id) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER recurring_rule_tags_types_update BEFORE UPDATE ON recurring_rule_tags
WHEN (typeof(NEW.rule_id) IN ('text') AND typeof(NEW.tag_id) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `recurring_executions` (`id` TEXT NOT NULL, `rule_id` TEXT NOT NULL, `scheduled_at` INTEGER NOT NULL, `status` TEXT NOT NULL, `transaction_id` TEXT, `attempt_count` INTEGER NOT NULL, `last_error` TEXT, `created_at_epoch_millis` INTEGER NOT NULL, `updated_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`rule_id`) REFERENCES `recurring_rules`(`id`) ON UPDATE CASCADE ON DELETE CASCADE , FOREIGN KEY(`transaction_id`) REFERENCES `transactions`(`id`) ON UPDATE CASCADE ON DELETE RESTRICT );

CREATE UNIQUE INDEX IF NOT EXISTS `index_recurring_executions_occurrence` ON `recurring_executions` (`rule_id`, `scheduled_at`);

CREATE INDEX IF NOT EXISTS `index_recurring_executions_transaction` ON `recurring_executions` (`transaction_id`);

CREATE INDEX IF NOT EXISTS `index_recurring_executions_status` ON `recurring_executions` (`status`, `updated_at_epoch_millis`);

CREATE TRIGGER recurring_executions_types_insert BEFORE INSERT ON recurring_executions
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.rule_id) IN ('text') AND typeof(NEW.scheduled_at) IN ('integer') AND typeof(NEW.status) IN ('text') AND typeof(NEW.transaction_id) IN ('text', 'null') AND typeof(NEW.attempt_count) IN ('integer') AND typeof(NEW.last_error) IN ('text', 'null') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER recurring_executions_types_update BEFORE UPDATE ON recurring_executions
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.rule_id) IN ('text') AND typeof(NEW.scheduled_at) IN ('integer') AND typeof(NEW.status) IN ('text') AND typeof(NEW.transaction_id) IN ('text', 'null') AND typeof(NEW.attempt_count) IN ('integer') AND typeof(NEW.last_error) IN ('text', 'null') AND typeof(NEW.created_at_epoch_millis) IN ('integer') AND typeof(NEW.updated_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `crypto_price_quotes` (`asset_code` TEXT NOT NULL, `base_code` TEXT NOT NULL, `provider_id` TEXT NOT NULL, `price_text` TEXT NOT NULL, `venue` TEXT NOT NULL, `data_timestamp` INTEGER NOT NULL, `fetched_at` INTEGER NOT NULL, `expires_at` INTEGER NOT NULL, PRIMARY KEY(`asset_code`, `base_code`, `provider_id`), FOREIGN KEY(`asset_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE CASCADE , FOREIGN KEY(`base_code`) REFERENCES `currencies`(`code`) ON UPDATE CASCADE ON DELETE CASCADE );

CREATE INDEX IF NOT EXISTS `index_crypto_price_quotes_base_code` ON `crypto_price_quotes` (`base_code`);

CREATE TRIGGER crypto_price_quotes_types_insert BEFORE INSERT ON crypto_price_quotes
WHEN (typeof(NEW.asset_code) IN ('text') AND typeof(NEW.base_code) IN ('text') AND typeof(NEW.provider_id) IN ('text') AND typeof(NEW.price_text) IN ('text') AND typeof(NEW.venue) IN ('text') AND typeof(NEW.data_timestamp) IN ('integer') AND typeof(NEW.fetched_at) IN ('integer') AND typeof(NEW.expires_at) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER crypto_price_quotes_types_update BEFORE UPDATE ON crypto_price_quotes
WHEN (typeof(NEW.asset_code) IN ('text') AND typeof(NEW.base_code) IN ('text') AND typeof(NEW.provider_id) IN ('text') AND typeof(NEW.price_text) IN ('text') AND typeof(NEW.venue) IN ('text') AND typeof(NEW.data_timestamp) IN ('integer') AND typeof(NEW.fetched_at) IN ('integer') AND typeof(NEW.expires_at) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `anomaly_feedback` (`id` TEXT NOT NULL, `feedback_type` TEXT NOT NULL, `kind` TEXT NOT NULL, `category_id` TEXT, `base_currency_code` TEXT NOT NULL, `amount_minor_text` TEXT NOT NULL, `base_scale` INTEGER NOT NULL, `feature_version` INTEGER NOT NULL, `created_at_epoch_millis` INTEGER NOT NULL, PRIMARY KEY(`id`));

CREATE TRIGGER anomaly_feedback_types_insert BEFORE INSERT ON anomaly_feedback
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.feedback_type) IN ('text') AND typeof(NEW.kind) IN ('text') AND typeof(NEW.category_id) IN ('text', 'null') AND typeof(NEW.base_currency_code) IN ('text') AND typeof(NEW.amount_minor_text) IN ('text') AND typeof(NEW.base_scale) IN ('integer') AND typeof(NEW.feature_version) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER anomaly_feedback_types_update BEFORE UPDATE ON anomaly_feedback
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.feedback_type) IN ('text') AND typeof(NEW.kind) IN ('text') AND typeof(NEW.category_id) IN ('text', 'null') AND typeof(NEW.base_currency_code) IN ('text') AND typeof(NEW.amount_minor_text) IN ('text') AND typeof(NEW.base_scale) IN ('integer') AND typeof(NEW.feature_version) IN ('integer') AND typeof(NEW.created_at_epoch_millis) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `restore_state` (`id` INTEGER NOT NULL, `settings` TEXT NOT NULL, PRIMARY KEY(`id`));

CREATE TRIGGER restore_state_types_insert BEFORE INSERT ON restore_state
WHEN (typeof(NEW.id) IN ('integer') AND typeof(NEW.settings) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER restore_state_types_update BEFORE UPDATE ON restore_state
WHEN (typeof(NEW.id) IN ('integer') AND typeof(NEW.settings) IN ('text')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `account_fund_openings` (`id` TEXT NOT NULL, `account_id` TEXT NOT NULL, `revision` INTEGER NOT NULL, `kind` TEXT NOT NULL, `enabled` INTEGER NOT NULL, `currency_code` TEXT NOT NULL, `scale` INTEGER NOT NULL, `amount_minor` INTEGER, `started_at` INTEGER NOT NULL, `created_at` INTEGER NOT NULL, PRIMARY KEY(`id`), FOREIGN KEY(`account_id`) REFERENCES `accounts`(`id`) ON UPDATE NO ACTION ON DELETE RESTRICT , FOREIGN KEY(`currency_code`) REFERENCES `currencies`(`code`) ON UPDATE NO ACTION ON DELETE RESTRICT );

CREATE UNIQUE INDEX IF NOT EXISTS `index_account_fund_openings_account_id_revision` ON `account_fund_openings` (`account_id`, `revision`);

CREATE INDEX IF NOT EXISTS `index_account_fund_openings_currency_code` ON `account_fund_openings` (`currency_code`);

CREATE TRIGGER account_fund_openings_types_insert BEFORE INSERT ON account_fund_openings
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.revision) IN ('integer') AND typeof(NEW.kind) IN ('text') AND typeof(NEW.enabled) IN ('integer') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.scale) IN ('integer') AND typeof(NEW.amount_minor) IN ('integer', 'null') AND typeof(NEW.started_at) IN ('integer') AND typeof(NEW.created_at) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER account_fund_openings_types_update BEFORE UPDATE ON account_fund_openings
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.account_id) IN ('text') AND typeof(NEW.revision) IN ('integer') AND typeof(NEW.kind) IN ('text') AND typeof(NEW.enabled) IN ('integer') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.scale) IN ('integer') AND typeof(NEW.amount_minor) IN ('integer', 'null') AND typeof(NEW.started_at) IN ('integer') AND typeof(NEW.created_at) IN ('integer')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TABLE IF NOT EXISTS `account_transfers` (`id` TEXT NOT NULL, `request_key` TEXT NOT NULL, `from_account_id` TEXT NOT NULL, `to_account_id` TEXT NOT NULL, `from_kind` TEXT NOT NULL, `to_kind` TEXT NOT NULL, `currency_code` TEXT NOT NULL, `scale` INTEGER NOT NULL, `principal_minor` INTEGER NOT NULL, `profit_minor` INTEGER NOT NULL, `profit_category_id` TEXT, `profit_transaction_id` TEXT, `occurred_at` INTEGER NOT NULL, `zone_id` TEXT NOT NULL, `note` TEXT, `created_at` INTEGER NOT NULL, `updated_at` INTEGER NOT NULL, `deleted_at` INTEGER, PRIMARY KEY(`id`), FOREIGN KEY(`from_account_id`) REFERENCES `accounts`(`id`) ON UPDATE NO ACTION ON DELETE RESTRICT , FOREIGN KEY(`to_account_id`) REFERENCES `accounts`(`id`) ON UPDATE NO ACTION ON DELETE RESTRICT , FOREIGN KEY(`currency_code`) REFERENCES `currencies`(`code`) ON UPDATE NO ACTION ON DELETE RESTRICT , FOREIGN KEY(`profit_category_id`) REFERENCES `categories`(`id`) ON UPDATE NO ACTION ON DELETE RESTRICT , FOREIGN KEY(`profit_transaction_id`) REFERENCES `transactions`(`id`) ON UPDATE NO ACTION ON DELETE RESTRICT );

CREATE UNIQUE INDEX IF NOT EXISTS `index_account_transfers_request_key` ON `account_transfers` (`request_key`);

CREATE INDEX IF NOT EXISTS `index_account_transfers_from_account_id` ON `account_transfers` (`from_account_id`);

CREATE INDEX IF NOT EXISTS `index_account_transfers_to_account_id` ON `account_transfers` (`to_account_id`);

CREATE INDEX IF NOT EXISTS `index_account_transfers_currency_code` ON `account_transfers` (`currency_code`);

CREATE INDEX IF NOT EXISTS `index_account_transfers_profit_category_id` ON `account_transfers` (`profit_category_id`);

CREATE UNIQUE INDEX IF NOT EXISTS `index_account_transfers_profit_transaction_id` ON `account_transfers` (`profit_transaction_id`);

CREATE INDEX IF NOT EXISTS `index_account_transfers_occurred_at` ON `account_transfers` (`occurred_at`);

CREATE TRIGGER account_transfers_types_insert BEFORE INSERT ON account_transfers
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.request_key) IN ('text') AND typeof(NEW.from_account_id) IN ('text') AND typeof(NEW.to_account_id) IN ('text') AND typeof(NEW.from_kind) IN ('text') AND typeof(NEW.to_kind) IN ('text') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.scale) IN ('integer') AND typeof(NEW.principal_minor) IN ('integer') AND typeof(NEW.profit_minor) IN ('integer') AND typeof(NEW.profit_category_id) IN ('text', 'null') AND typeof(NEW.profit_transaction_id) IN ('text', 'null') AND typeof(NEW.occurred_at) IN ('integer') AND typeof(NEW.zone_id) IN ('text') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.created_at) IN ('integer') AND typeof(NEW.updated_at) IN ('integer') AND typeof(NEW.deleted_at) IN ('integer', 'null')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE TRIGGER account_transfers_types_update BEFORE UPDATE ON account_transfers
WHEN (typeof(NEW.id) IN ('text') AND typeof(NEW.request_key) IN ('text') AND typeof(NEW.from_account_id) IN ('text') AND typeof(NEW.to_account_id) IN ('text') AND typeof(NEW.from_kind) IN ('text') AND typeof(NEW.to_kind) IN ('text') AND typeof(NEW.currency_code) IN ('text') AND typeof(NEW.scale) IN ('integer') AND typeof(NEW.principal_minor) IN ('integer') AND typeof(NEW.profit_minor) IN ('integer') AND typeof(NEW.profit_category_id) IN ('text', 'null') AND typeof(NEW.profit_transaction_id) IN ('text', 'null') AND typeof(NEW.occurred_at) IN ('integer') AND typeof(NEW.zone_id) IN ('text') AND typeof(NEW.note) IN ('text', 'null') AND typeof(NEW.created_at) IN ('integer') AND typeof(NEW.updated_at) IN ('integer') AND typeof(NEW.deleted_at) IN ('integer', 'null')) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid storage value type'); END;

CREATE UNIQUE INDEX index_accounts_single_default ON accounts(is_default) WHERE is_default = 1 AND is_archived = 0;

CREATE TRIGGER currencies_validate_insert BEFORE INSERT ON currencies
WHEN (NEW.code <> '' AND NEW.asset_type IN ('FIAT','CRYPTO') AND NEW.display_name <> '' AND NEW.symbol <> '' AND NEW.default_scale BETWEEN 0 AND 18 AND NEW.is_enabled IN (0,1) AND NEW.metadata_version > 0) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid currencies'); END;

CREATE TRIGGER currencies_validate_update BEFORE UPDATE ON currencies
WHEN (NEW.code <> '' AND NEW.asset_type IN ('FIAT','CRYPTO') AND NEW.display_name <> '' AND NEW.symbol <> '' AND NEW.default_scale BETWEEN 0 AND 18 AND NEW.is_enabled IN (0,1) AND NEW.metadata_version > 0) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid currencies'); END;

CREATE TRIGGER categories_validate_insert BEFORE INSERT ON categories
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.icon_key <> ''
AND NEW.color_key <> ''
AND NEW.icon_source IN ('BUILT_IN', 'EMOJI', 'IMAGE')
AND NEW.background_focus IN ('TOP', 'CENTER', 'BOTTOM')
AND (
    (NEW.icon_source = 'BUILT_IN' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'EMOJI' AND NEW.emoji IS NOT NULL AND NEW.emoji <> '' AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'IMAGE' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NOT NULL)
)
AND (
    NEW.icon_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.icon_asset_id AND asset.asset_kind = 'ICON')
)
AND (
    NEW.background_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.background_asset_id AND asset.asset_kind = 'BACKGROUND')
)
AND NEW.is_archived IN (0, 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (NEW.parent_id IS NULL OR NEW.parent_id <> NEW.id)
AND (
    NEW.parent_id IS NULL
    OR EXISTS (
        SELECT 1 FROM categories parent
        WHERE parent.id = NEW.parent_id
          AND parent.parent_id IS NULL
          AND parent.transaction_type = NEW.transaction_type
    )
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid categories'); END;

CREATE TRIGGER categories_validate_update BEFORE UPDATE ON categories
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.icon_key <> ''
AND NEW.color_key <> ''
AND NEW.icon_source IN ('BUILT_IN', 'EMOJI', 'IMAGE')
AND NEW.background_focus IN ('TOP', 'CENTER', 'BOTTOM')
AND (
    (NEW.icon_source = 'BUILT_IN' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'EMOJI' AND NEW.emoji IS NOT NULL AND NEW.emoji <> '' AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'IMAGE' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NOT NULL)
)
AND (
    NEW.icon_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.icon_asset_id AND asset.asset_kind = 'ICON')
)
AND (
    NEW.background_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.background_asset_id AND asset.asset_kind = 'BACKGROUND')
)
AND NEW.is_archived IN (0, 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (NEW.parent_id IS NULL OR NEW.parent_id <> NEW.id)
AND (
    NEW.parent_id IS NULL
    OR EXISTS (
        SELECT 1 FROM categories parent
        WHERE parent.id = NEW.parent_id
          AND parent.parent_id IS NULL
          AND parent.transaction_type = NEW.transaction_type
    )
) AND NOT (NEW.parent_id IS NOT NULL AND EXISTS (SELECT 1 FROM categories child WHERE child.parent_id = NEW.id)) AND NOT EXISTS (SELECT 1 FROM categories child WHERE child.parent_id = NEW.id AND child.transaction_type <> NEW.transaction_type)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid categories'); END;

CREATE TRIGGER accounts_validate_insert BEFORE INSERT ON accounts
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.icon_key <> ''
AND NEW.color_key <> ''
AND NEW.icon_source IN ('BUILT_IN', 'EMOJI', 'IMAGE')
AND NEW.background_focus IN ('TOP', 'CENTER', 'BOTTOM')
AND (
    (NEW.icon_source = 'BUILT_IN' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'EMOJI' AND NEW.emoji IS NOT NULL AND NEW.emoji <> '' AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'IMAGE' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NOT NULL)
)
AND (
    NEW.icon_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.icon_asset_id AND asset.asset_kind = 'ICON')
)
AND (
    NEW.background_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.background_asset_id AND asset.asset_kind = 'BACKGROUND')
)
AND NEW.is_default IN (0, 1)
AND NEW.is_archived IN (0, 1)
AND NOT (NEW.is_default = 1 AND NEW.is_archived = 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid accounts'); END;

CREATE TRIGGER accounts_validate_update BEFORE UPDATE ON accounts
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.icon_key <> ''
AND NEW.color_key <> ''
AND NEW.icon_source IN ('BUILT_IN', 'EMOJI', 'IMAGE')
AND NEW.background_focus IN ('TOP', 'CENTER', 'BOTTOM')
AND (
    (NEW.icon_source = 'BUILT_IN' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'EMOJI' AND NEW.emoji IS NOT NULL AND NEW.emoji <> '' AND NEW.icon_asset_id IS NULL)
    OR (NEW.icon_source = 'IMAGE' AND NEW.emoji IS NULL AND NEW.icon_asset_id IS NOT NULL)
)
AND (
    NEW.icon_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.icon_asset_id AND asset.asset_kind = 'ICON')
)
AND (
    NEW.background_asset_id IS NULL
    OR EXISTS (SELECT 1 FROM visual_assets asset WHERE asset.id = NEW.background_asset_id AND asset.asset_kind = 'BACKGROUND')
)
AND NEW.is_default IN (0, 1)
AND NEW.is_archived IN (0, 1)
AND NOT (NEW.is_default = 1 AND NEW.is_archived = 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid accounts'); END;

CREATE TRIGGER tags_validate_insert BEFORE INSERT ON tags
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.normalized_name <> ''
AND NEW.color_key <> ''
AND NEW.is_archived IN (0, 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid tags'); END;

CREATE TRIGGER tags_validate_update BEFORE UPDATE ON tags
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.normalized_name <> ''
AND NEW.color_key <> ''
AND NEW.is_archived IN (0, 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid tags'); END;

CREATE TRIGGER transactions_validate_insert BEFORE INSERT ON transactions
WHEN (NEW.id <> ''
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.original_amount_minor > 0
AND NEW.converted_base_amount_minor > 0
AND NEW.original_scale BETWEEN 0 AND 18
AND NEW.base_scale BETWEEN 0 AND 18
AND NEW.exchange_rate_text <> ''
AND NEW.rate_provider <> ''
AND NEW.valuation_method IN (
    'IDENTITY', 'ACTUAL_SETTLEMENT', 'MANUAL_RATE', 'LATEST_RATE',
    'HISTORICAL_RATE', 'CURRENT_FALLBACK', 'CACHED_FALLBACK', 'MARKET_PRICE', 'CACHED_MARKET_PRICE'
)
AND NEW.category_id <> ''
AND NEW.account_id <> ''
AND NEW.occurred_zone_id <> ''
AND NEW.source_type IN ('MANUAL', 'TEMPLATE', 'RECURRING')
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (
    NEW.deleted_at_epoch_millis IS NULL
    OR NEW.deleted_at_epoch_millis BETWEEN
        NEW.created_at_epoch_millis AND NEW.updated_at_epoch_millis
)
AND (NEW.request_key IS NULL OR NEW.request_key <> '')
AND (
    (NEW.source_type = 'MANUAL' AND NEW.source_id IS NULL)
    OR (
        NEW.source_type IN ('TEMPLATE', 'RECURRING')
        AND NEW.source_id IS NOT NULL
        AND NEW.source_id <> ''
    )
)
AND (
    (
        NEW.original_currency_code = NEW.base_currency_code
        AND NEW.exchange_rate_text = '1'
        AND NEW.rate_provider = 'IDENTITY'
        AND NEW.valuation_method = 'IDENTITY'
        AND NEW.rate_data_timestamp IS NULL
        AND NEW.rate_fetched_at IS NULL
        AND NEW.original_amount_minor = NEW.converted_base_amount_minor
        AND NEW.original_scale = NEW.base_scale
    )
    OR (
        NEW.original_currency_code <> NEW.base_currency_code
        AND NEW.rate_provider <> 'IDENTITY'
        AND NEW.valuation_method <> 'IDENTITY'
    )
)
AND (
    NEW.valuation_method NOT IN (
        'LATEST_RATE', 'HISTORICAL_RATE', 'CURRENT_FALLBACK', 'CACHED_FALLBACK'
    )
    OR (NEW.rate_data_timestamp IS NOT NULL AND NEW.rate_fetched_at IS NOT NULL)
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid transactions'); END;

CREATE TRIGGER transactions_validate_update BEFORE UPDATE ON transactions
WHEN (NEW.id <> ''
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.original_amount_minor > 0
AND NEW.converted_base_amount_minor > 0
AND NEW.original_scale BETWEEN 0 AND 18
AND NEW.base_scale BETWEEN 0 AND 18
AND NEW.exchange_rate_text <> ''
AND NEW.rate_provider <> ''
AND NEW.valuation_method IN (
    'IDENTITY', 'ACTUAL_SETTLEMENT', 'MANUAL_RATE', 'LATEST_RATE',
    'HISTORICAL_RATE', 'CURRENT_FALLBACK', 'CACHED_FALLBACK', 'MARKET_PRICE', 'CACHED_MARKET_PRICE'
)
AND NEW.category_id <> ''
AND NEW.account_id <> ''
AND NEW.occurred_zone_id <> ''
AND NEW.source_type IN ('MANUAL', 'TEMPLATE', 'RECURRING')
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (
    NEW.deleted_at_epoch_millis IS NULL
    OR NEW.deleted_at_epoch_millis BETWEEN
        NEW.created_at_epoch_millis AND NEW.updated_at_epoch_millis
)
AND (NEW.request_key IS NULL OR NEW.request_key <> '')
AND (
    (NEW.source_type = 'MANUAL' AND NEW.source_id IS NULL)
    OR (
        NEW.source_type IN ('TEMPLATE', 'RECURRING')
        AND NEW.source_id IS NOT NULL
        AND NEW.source_id <> ''
    )
)
AND (
    (
        NEW.original_currency_code = NEW.base_currency_code
        AND NEW.exchange_rate_text = '1'
        AND NEW.rate_provider = 'IDENTITY'
        AND NEW.valuation_method = 'IDENTITY'
        AND NEW.rate_data_timestamp IS NULL
        AND NEW.rate_fetched_at IS NULL
        AND NEW.original_amount_minor = NEW.converted_base_amount_minor
        AND NEW.original_scale = NEW.base_scale
    )
    OR (
        NEW.original_currency_code <> NEW.base_currency_code
        AND NEW.rate_provider <> 'IDENTITY'
        AND NEW.valuation_method <> 'IDENTITY'
    )
)
AND (
    NEW.valuation_method NOT IN (
        'LATEST_RATE', 'HISTORICAL_RATE', 'CURRENT_FALLBACK', 'CACHED_FALLBACK'
    )
    OR (NEW.rate_data_timestamp IS NOT NULL AND NEW.rate_fetched_at IS NOT NULL)
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid transactions'); END;

CREATE TRIGGER visual_assets_validate_insert BEFORE INSERT ON visual_assets
WHEN (NEW.id <> ''
AND NEW.asset_kind IN ('ICON', 'BACKGROUND')
AND NEW.relative_path <> ''
AND substr(NEW.relative_path, 1, 1) <> '/'
AND instr(NEW.relative_path, ':') = 0
AND instr(NEW.relative_path, '..') = 0
AND NEW.mime_type LIKE 'image/%'
AND NEW.width_px > 0
AND NEW.height_px > 0
AND NEW.byte_size > 0
AND length(NEW.content_sha256) = 64
AND NEW.processing_version > 0) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid visual_assets'); END;

CREATE TRIGGER visual_assets_validate_update BEFORE UPDATE ON visual_assets
WHEN (NEW.id <> ''
AND NEW.asset_kind IN ('ICON', 'BACKGROUND')
AND NEW.relative_path <> ''
AND substr(NEW.relative_path, 1, 1) <> '/'
AND instr(NEW.relative_path, ':') = 0
AND instr(NEW.relative_path, '..') = 0
AND NEW.mime_type LIKE 'image/%'
AND NEW.width_px > 0
AND NEW.height_px > 0
AND NEW.byte_size > 0
AND length(NEW.content_sha256) = 64
AND NEW.processing_version > 0) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid visual_assets'); END;

CREATE TRIGGER fx_quotes_validate_insert BEFORE INSERT ON fx_quotes
WHEN (NEW.id <> ''
AND NEW.original_currency_code <> NEW.base_currency_code
AND NEW.rate_text <> ''
AND NEW.provider_id <> ''
AND NEW.rate_data_timestamp > 0
AND NEW.fetched_at > 0
AND NEW.expires_at >= NEW.rate_data_timestamp
AND NEW.quote_kind IN ('LATEST', 'HISTORICAL')
AND (
    (NEW.quote_kind = 'LATEST' AND NEW.rate_date_epoch_day IS NULL)
    OR (NEW.quote_kind = 'HISTORICAL' AND NEW.rate_date_epoch_day IS NOT NULL)
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid fx_quotes'); END;

CREATE TRIGGER fx_quotes_validate_update BEFORE UPDATE ON fx_quotes
WHEN (NEW.id <> ''
AND NEW.original_currency_code <> NEW.base_currency_code
AND NEW.rate_text <> ''
AND NEW.provider_id <> ''
AND NEW.rate_data_timestamp > 0
AND NEW.fetched_at > 0
AND NEW.expires_at >= NEW.rate_data_timestamp
AND NEW.quote_kind IN ('LATEST', 'HISTORICAL')
AND (
    (NEW.quote_kind = 'LATEST' AND NEW.rate_date_epoch_day IS NULL)
    OR (NEW.quote_kind = 'HISTORICAL' AND NEW.rate_date_epoch_day IS NOT NULL)
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid fx_quotes'); END;

CREATE TRIGGER quick_templates_validate_insert BEFORE INSERT ON quick_templates
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.icon_key <> ''
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.amount_minor > 0
AND NEW.amount_scale BETWEEN 0 AND 18
AND NEW.category_id <> ''
AND NEW.account_id <> ''
AND NEW.usage_count >= 0
AND NEW.is_archived IN (0, 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (
    NEW.last_used_at IS NULL
    OR NEW.last_used_at BETWEEN NEW.created_at_epoch_millis AND NEW.updated_at_epoch_millis
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid quick_templates'); END;

CREATE TRIGGER quick_templates_validate_update BEFORE UPDATE ON quick_templates
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.icon_key <> ''
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.amount_minor > 0
AND NEW.amount_scale BETWEEN 0 AND 18
AND NEW.category_id <> ''
AND NEW.account_id <> ''
AND NEW.usage_count >= 0
AND NEW.is_archived IN (0, 1)
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (
    NEW.last_used_at IS NULL
    OR NEW.last_used_at BETWEEN NEW.created_at_epoch_millis AND NEW.updated_at_epoch_millis
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid quick_templates'); END;

CREATE TRIGGER recurring_rules_validate_insert BEFORE INSERT ON recurring_rules
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.is_enabled IN (0, 1)
AND (NEW.end_local_epoch_day IS NULL OR NEW.end_local_epoch_day >= NEW.start_local_epoch_day)
AND NEW.scheduled_local_time_minutes BETWEEN 0 AND 1439
AND NEW.zone_id <> ''
AND NEW.rule_version > 0
AND NEW.catch_up_policy IN ('SKIP_MISSED', 'CREATE_MISSED')
AND NEW.frequency IN ('DAILY', 'WEEKDAYS', 'WEEKLY_SET', 'MONTHLY', 'YEARLY', 'INTERVAL')
AND NEW.interval_value > 0
AND (NEW.interval_unit IS NULL OR NEW.interval_unit IN ('DAY', 'WEEK', 'MONTH', 'YEAR'))
AND NEW.weekdays_mask BETWEEN 0 AND 127
AND (NEW.day_of_month IS NULL OR NEW.day_of_month BETWEEN 1 AND 31)
AND (NEW.month_of_year IS NULL OR NEW.month_of_year BETWEEN 1 AND 12)
AND NEW.month_day_policy IN ('LAST_DAY', 'SKIP')
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.amount_minor > 0
AND NEW.amount_scale BETWEEN 0 AND 18
AND NEW.category_id <> ''
AND NEW.account_id <> ''
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (NEW.last_evaluated_at IS NULL OR NEW.last_evaluated_at >= NEW.created_at_epoch_millis)
AND (
    (NEW.frequency = 'WEEKLY_SET' AND NEW.weekdays_mask <> 0)
    OR NEW.frequency <> 'WEEKLY_SET'
)
AND (
    (NEW.frequency = 'MONTHLY' AND NEW.day_of_month IS NOT NULL)
    OR NEW.frequency <> 'MONTHLY'
)
AND (
    (NEW.frequency = 'YEARLY' AND NEW.day_of_month IS NOT NULL AND NEW.month_of_year IS NOT NULL)
    OR NEW.frequency <> 'YEARLY'
)
AND (
    (NEW.frequency = 'INTERVAL' AND NEW.interval_unit IS NOT NULL)
    OR NEW.frequency <> 'INTERVAL'
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid recurring_rules'); END;

CREATE TRIGGER recurring_rules_validate_update BEFORE UPDATE ON recurring_rules
WHEN (NEW.id <> ''
AND NEW.name <> ''
AND NEW.is_enabled IN (0, 1)
AND (NEW.end_local_epoch_day IS NULL OR NEW.end_local_epoch_day >= NEW.start_local_epoch_day)
AND NEW.scheduled_local_time_minutes BETWEEN 0 AND 1439
AND NEW.zone_id <> ''
AND NEW.rule_version > 0
AND NEW.catch_up_policy IN ('SKIP_MISSED', 'CREATE_MISSED')
AND NEW.frequency IN ('DAILY', 'WEEKDAYS', 'WEEKLY_SET', 'MONTHLY', 'YEARLY', 'INTERVAL')
AND NEW.interval_value > 0
AND (NEW.interval_unit IS NULL OR NEW.interval_unit IN ('DAY', 'WEEK', 'MONTH', 'YEAR'))
AND NEW.weekdays_mask BETWEEN 0 AND 127
AND (NEW.day_of_month IS NULL OR NEW.day_of_month BETWEEN 1 AND 31)
AND (NEW.month_of_year IS NULL OR NEW.month_of_year BETWEEN 1 AND 12)
AND NEW.month_day_policy IN ('LAST_DAY', 'SKIP')
AND NEW.transaction_type IN ('EXPENSE', 'INCOME')
AND NEW.amount_minor > 0
AND NEW.amount_scale BETWEEN 0 AND 18
AND NEW.category_id <> ''
AND NEW.account_id <> ''
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND (NEW.last_evaluated_at IS NULL OR NEW.last_evaluated_at >= NEW.created_at_epoch_millis)
AND (
    (NEW.frequency = 'WEEKLY_SET' AND NEW.weekdays_mask <> 0)
    OR NEW.frequency <> 'WEEKLY_SET'
)
AND (
    (NEW.frequency = 'MONTHLY' AND NEW.day_of_month IS NOT NULL)
    OR NEW.frequency <> 'MONTHLY'
)
AND (
    (NEW.frequency = 'YEARLY' AND NEW.day_of_month IS NOT NULL AND NEW.month_of_year IS NOT NULL)
    OR NEW.frequency <> 'YEARLY'
)
AND (
    (NEW.frequency = 'INTERVAL' AND NEW.interval_unit IS NOT NULL)
    OR NEW.frequency <> 'INTERVAL'
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid recurring_rules'); END;

CREATE TRIGGER recurring_executions_validate_insert BEFORE INSERT ON recurring_executions
WHEN (NEW.id <> ''
AND NEW.rule_id <> ''
AND NEW.status IN ('PENDING', 'CREATED', 'SKIPPED', 'FAILED_RETRYABLE', 'FAILED_FINAL')
AND NEW.attempt_count >= 0
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND ((NEW.status = 'CREATED') = (NEW.transaction_id IS NOT NULL))
AND (
    (NEW.status IN ('FAILED_RETRYABLE', 'FAILED_FINAL')) = (NEW.last_error IS NOT NULL)
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid recurring_executions'); END;

CREATE TRIGGER recurring_executions_validate_update BEFORE UPDATE ON recurring_executions
WHEN (NEW.id <> ''
AND NEW.rule_id <> ''
AND NEW.status IN ('PENDING', 'CREATED', 'SKIPPED', 'FAILED_RETRYABLE', 'FAILED_FINAL')
AND NEW.attempt_count >= 0
AND NEW.updated_at_epoch_millis >= NEW.created_at_epoch_millis
AND ((NEW.status = 'CREATED') = (NEW.transaction_id IS NOT NULL))
AND (
    (NEW.status IN ('FAILED_RETRYABLE', 'FAILED_FINAL')) = (NEW.last_error IS NOT NULL)
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid recurring_executions'); END;

CREATE TRIGGER crypto_transaction_insert BEFORE INSERT ON transactions
WHEN ((
  ((SELECT asset_type FROM currencies WHERE code = NEW.original_currency_code) <> 'CRYPTO'
    AND NEW.crypto_price_text IS NULL AND NEW.crypto_price_kind IS NULL
    AND NEW.crypto_price_source IS NULL AND NEW.crypto_venue IS NULL AND NEW.crypto_pair IS NULL
    AND NEW.crypto_data_timestamp IS NULL AND NEW.crypto_fetched_at IS NULL
    AND NEW.valuation_method NOT IN ('MARKET_PRICE','CACHED_MARKET_PRICE'))
  OR
  ((SELECT asset_type FROM currencies WHERE code = NEW.original_currency_code) = 'CRYPTO'
    AND (SELECT asset_type FROM currencies WHERE code = NEW.base_currency_code) = 'FIAT'
    AND NEW.crypto_price_text IS NOT NULL AND NEW.crypto_price_text = NEW.exchange_rate_text
    AND NEW.crypto_price_source IS NOT NULL AND NEW.crypto_price_source = NEW.rate_provider
    AND NEW.crypto_venue IS NOT NULL AND NEW.crypto_venue <> ''
    AND NEW.crypto_price_kind IS NOT NULL AND NEW.crypto_pair IS NOT NULL
    AND NEW.crypto_pair = NEW.original_currency_code || '/' || NEW.base_currency_code
    AND ((NEW.crypto_price_kind = 'ACTUAL_PRICE' AND NEW.valuation_method = 'MANUAL_RATE'
            AND NEW.crypto_data_timestamp IS NULL AND NEW.crypto_fetched_at IS NULL)
      OR (NEW.crypto_price_kind = 'ACTUAL_SETTLEMENT' AND NEW.valuation_method = 'ACTUAL_SETTLEMENT'
            AND NEW.crypto_data_timestamp IS NULL AND NEW.crypto_fetched_at IS NULL)
      OR (NEW.crypto_price_kind = 'MARKET_REFERENCE' AND NEW.valuation_method IN ('MARKET_PRICE','CACHED_MARKET_PRICE')
            AND NEW.crypto_data_timestamp IS NOT NULL AND NEW.crypto_fetched_at IS NOT NULL
            AND NEW.crypto_data_timestamp > 0 AND NEW.crypto_fetched_at > 0
            AND NEW.crypto_data_timestamp = NEW.rate_data_timestamp AND NEW.crypto_fetched_at = NEW.rate_fetched_at)))
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid crypto valuation snapshot'); END;

CREATE TRIGGER crypto_transaction_update BEFORE UPDATE ON transactions
WHEN ((
  ((SELECT asset_type FROM currencies WHERE code = NEW.original_currency_code) <> 'CRYPTO'
    AND NEW.crypto_price_text IS NULL AND NEW.crypto_price_kind IS NULL
    AND NEW.crypto_price_source IS NULL AND NEW.crypto_venue IS NULL AND NEW.crypto_pair IS NULL
    AND NEW.crypto_data_timestamp IS NULL AND NEW.crypto_fetched_at IS NULL
    AND NEW.valuation_method NOT IN ('MARKET_PRICE','CACHED_MARKET_PRICE'))
  OR
  ((SELECT asset_type FROM currencies WHERE code = NEW.original_currency_code) = 'CRYPTO'
    AND (SELECT asset_type FROM currencies WHERE code = NEW.base_currency_code) = 'FIAT'
    AND NEW.crypto_price_text IS NOT NULL AND NEW.crypto_price_text = NEW.exchange_rate_text
    AND NEW.crypto_price_source IS NOT NULL AND NEW.crypto_price_source = NEW.rate_provider
    AND NEW.crypto_venue IS NOT NULL AND NEW.crypto_venue <> ''
    AND NEW.crypto_price_kind IS NOT NULL AND NEW.crypto_pair IS NOT NULL
    AND NEW.crypto_pair = NEW.original_currency_code || '/' || NEW.base_currency_code
    AND ((NEW.crypto_price_kind = 'ACTUAL_PRICE' AND NEW.valuation_method = 'MANUAL_RATE'
            AND NEW.crypto_data_timestamp IS NULL AND NEW.crypto_fetched_at IS NULL)
      OR (NEW.crypto_price_kind = 'ACTUAL_SETTLEMENT' AND NEW.valuation_method = 'ACTUAL_SETTLEMENT'
            AND NEW.crypto_data_timestamp IS NULL AND NEW.crypto_fetched_at IS NULL)
      OR (NEW.crypto_price_kind = 'MARKET_REFERENCE' AND NEW.valuation_method IN ('MARKET_PRICE','CACHED_MARKET_PRICE')
            AND NEW.crypto_data_timestamp IS NOT NULL AND NEW.crypto_fetched_at IS NOT NULL
            AND NEW.crypto_data_timestamp > 0 AND NEW.crypto_fetched_at > 0
            AND NEW.crypto_data_timestamp = NEW.rate_data_timestamp AND NEW.crypto_fetched_at = NEW.rate_fetched_at)))
)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid crypto valuation snapshot'); END;

CREATE TRIGGER fund_openings_validate_insert BEFORE INSERT ON account_fund_openings
WHEN (NEW.id <> '' AND NEW.account_id <> '' AND NEW.revision >= 0 AND NEW.kind IN ('AVAILABLE','INVESTMENT_COST') AND NEW.scale BETWEEN 0 AND 18 AND ((NEW.enabled = 1 AND NEW.amount_minor IS NOT NULL AND NEW.amount_minor >= 0) OR (NEW.enabled = 0 AND NEW.amount_minor IS NULL))) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid funds opening'); END;

CREATE TRIGGER fund_openings_validate_update BEFORE UPDATE ON account_fund_openings
WHEN (NEW.id <> '' AND NEW.account_id <> '' AND NEW.revision >= 0 AND NEW.kind IN ('AVAILABLE','INVESTMENT_COST') AND NEW.scale BETWEEN 0 AND 18 AND ((NEW.enabled = 1 AND NEW.amount_minor IS NOT NULL AND NEW.amount_minor >= 0) OR (NEW.enabled = 0 AND NEW.amount_minor IS NULL))) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid funds opening'); END;

CREATE TRIGGER fund_transfers_validate_insert BEFORE INSERT ON account_transfers
WHEN (NEW.id <> '' AND NEW.request_key <> '' AND NEW.from_account_id <> '' AND NEW.to_account_id <> '' AND NEW.from_account_id <> NEW.to_account_id AND NEW.scale BETWEEN 0 AND 18 AND NEW.principal_minor >= 0 AND NEW.from_kind IN ('AVAILABLE','INVESTMENT_COST') AND NEW.to_kind IN ('AVAILABLE','INVESTMENT_COST') AND (NEW.principal_minor > 0 OR NEW.profit_minor > 0) AND CASE WHEN NEW.profit_minor >= 0 THEN NEW.principal_minor <= 9223372036854775807 - NEW.profit_minor WHEN NEW.profit_minor = -9223372036854775808 THEN 0 ELSE NEW.principal_minor >= -NEW.profit_minor END AND (NEW.profit_minor = 0 OR (NEW.from_kind = 'INVESTMENT_COST' AND NEW.to_kind = 'AVAILABLE')) AND ((NEW.profit_minor = 0 AND NEW.profit_category_id IS NULL) OR (NEW.profit_minor <> 0 AND NEW.profit_category_id IS NOT NULL AND NEW.profit_category_id <> '')) AND NEW.zone_id <> '' AND NEW.updated_at >= NEW.created_at AND (NEW.deleted_at IS NULL OR NEW.deleted_at BETWEEN NEW.created_at AND NEW.updated_at)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid account transfer'); END;

CREATE TRIGGER fund_transfers_validate_update BEFORE UPDATE ON account_transfers
WHEN (NEW.id <> '' AND NEW.request_key <> '' AND NEW.from_account_id <> '' AND NEW.to_account_id <> '' AND NEW.from_account_id <> NEW.to_account_id AND NEW.scale BETWEEN 0 AND 18 AND NEW.principal_minor >= 0 AND NEW.from_kind IN ('AVAILABLE','INVESTMENT_COST') AND NEW.to_kind IN ('AVAILABLE','INVESTMENT_COST') AND (NEW.principal_minor > 0 OR NEW.profit_minor > 0) AND CASE WHEN NEW.profit_minor >= 0 THEN NEW.principal_minor <= 9223372036854775807 - NEW.profit_minor WHEN NEW.profit_minor = -9223372036854775808 THEN 0 ELSE NEW.principal_minor >= -NEW.profit_minor END AND (NEW.profit_minor = 0 OR (NEW.from_kind = 'INVESTMENT_COST' AND NEW.to_kind = 'AVAILABLE')) AND ((NEW.profit_minor = 0 AND NEW.profit_category_id IS NULL) OR (NEW.profit_minor <> 0 AND NEW.profit_category_id IS NOT NULL AND NEW.profit_category_id <> '')) AND NEW.zone_id <> '' AND NEW.updated_at >= NEW.created_at AND (NEW.deleted_at IS NULL OR NEW.deleted_at BETWEEN NEW.created_at AND NEW.updated_at)) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'Invalid account transfer'); END;

PRAGMA application_id = 1129272137;

PRAGMA user_version = 1;
