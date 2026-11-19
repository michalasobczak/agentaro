require "test_helper"

# Spec 004, R2: application code must not use writes that skip callbacks, because they would bypass
# the data changelog. Audit pruning (HashChained) is the only allowed exception.
class NoBulkWritesTest < ActiveSupport::TestCase
  FORBIDDEN = /\b(update_all|delete_all|insert_all!?|upsert_all|update_columns?|delete_by)\b/
  ALLOWED = %w[app/models/concerns/hash_chained.rb].freeze

  test "no callback-skipping writes in app/ and lib/" do
    offenders = Dir[Rails.root.join("{app,lib}/**/*.{rb,rake}")].filter_map do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      next if ALLOWED.include?(relative)

      File.readlines(path).each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}: #{line.strip}" if line.match?(FORBIDDEN) && !line.lstrip.start_with?("#")
      end.presence
    end.flatten
    assert_empty offenders, "Use methods that run callbacks (see spec 004, R2)"
  end
end
