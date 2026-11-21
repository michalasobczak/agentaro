# Spec 031, G2: a fact the brain keeps about the user, a space or an agent — temporal: a contradicting newer fact
# supersedes it (invalid_at, superseded_by) and it stays in history (R3). Only the user deletes, permanently.
class MemoryFact < ApplicationRecord
  SUBJECTS = %w[user space agent].freeze
  KINDS = %w[preference decision fact constraint].freeze
  STATUSES = %w[proposed active invalid archived].freeze
  ORIGINS = %w[extracted remembered edited imported].freeze
  MAX = 300

  self.changelog_summarized = %w[embedding]
  self.changelog_ignored = %w[last_used_at use_count embedding embedding_model]

  belongs_to :user
  belongs_to :superseded_by, class_name: "MemoryFact", optional: true
  belongs_to :supersedes, class_name: "MemoryFact", optional: true
  has_many :memory_fact_sources, dependent: :destroy
  has_many :episodes, through: :memory_fact_sources, source: :memory_episode

  normalizes :statement, with: ->(value) { value.to_s.squish }
  validates :subject_type, inclusion: { in: SUBJECTS }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :statement, presence: true, length: { maximum: MAX }
  validates :confidence, numericality: { in: 0.0..1.0 }
  validates :subject_id, presence: true, unless: -> { subject_type == "user" }
  validate :no_secret

  before_validation { self.valid_from ||= Time.current }
  after_save_commit :index_text, if: -> { saved_change_to_statement? || saved_change_to_id? }
  after_destroy_commit :unindex_text
  before_destroy :release_links

  scope :active, -> { where(status: "active") }
  scope :proposed, -> { where(status: "proposed") }
  scope :current, -> { where(status: %w[active proposed]) }
  scope :about, ->(type, id = nil) { where(subject_type: type, subject_id: type == "user" ? nil : id) }

  # The subject as the extractor and the director name it: "user", "space:3", "agent:7".
  def subject_key = subject_type == "user" ? "user" : "#{subject_type}:#{subject_id}"

  def subject_record
    case subject_type
    when "space" then user.spaces.find_by(id: subject_id)
    when "agent" then Agent.find_by(id: subject_id)
    end
  end

  def subject_label
    case subject_type
    when "user" then user.username
    when "space" then subject_record ? "space \"#{subject_record.name}\"" : "a deleted space"
    else subject_record ? "agent #{subject_record.name}" : "a deleted agent"
    end
  end

  def history
    chain = []
    fact = supersedes
    while fact && chain.size < 20
      chain << fact
      fact = fact.supersedes
    end
    chain
  end

  # R3: this fact replaces older, which stays as history.
  def supersede!(older)
    transaction do
      update!(supersedes: older)
      older.update!(status: "invalid", invalid_at: Time.current, superseded_by: self) if older.status.in?(%w[active proposed])
    end
  end

  def invalidate! = update!(status: "invalid", invalid_at: Time.current)

  def vector = embedding && embedding.unpack("e*")

  def vector=(values)
    self.embedding = values && values.pack("e*")
  end

  # Keyword search (FTS5) over the user's facts: ids, best first.
  def self.keyword_ids(user, query, limit: 50)
    terms = query.to_s.downcase.scan(/[\p{L}\p{N}]{3,}/).uniq.first(24)
    return [] if terms.empty?

    match = terms.map { |t| "\"#{t}\"" }.join(" OR ")
    sql = "SELECT memory_facts.id FROM memory_facts_fts JOIN memory_facts ON memory_facts.id = memory_facts_fts.rowid " \
          "WHERE memory_facts_fts MATCH ? AND memory_facts.user_id = ? ORDER BY bm25(memory_facts_fts) LIMIT ?"
    connection.select_values(sanitize_sql_array([ sql, match, user.id, limit ]))
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("[brain] keyword search failed: #{e.message}")
    []
  end

  private

  def no_secret
    errors.add(:statement, "looks like it holds a secret (key, token or password); secrets are not remembered") if RunTrace.redact(statement).last
  end

  def index_text
    self.class.connection.exec_delete(sanitize("DELETE FROM memory_facts_fts WHERE rowid = ?", id))
    self.class.connection.exec_insert(sanitize("INSERT INTO memory_facts_fts(rowid, statement) VALUES (?, ?)", id, statement))
  end

  def unindex_text = self.class.connection.exec_delete(sanitize("DELETE FROM memory_facts_fts WHERE rowid = ?", id))

  def sanitize(sql, *values) = self.class.sanitize_sql_array([ sql, *values ])

  # Facts that point to this one keep their own history without it.
  def release_links
    MemoryFact.where(superseded_by_id: id).find_each { |f| f.update!(superseded_by_id: nil) }
    MemoryFact.where(supersedes_id: id).find_each { |f| f.update!(supersedes_id: nil) }
  end
end
