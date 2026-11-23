# Spec 051: a named group of the owner's spaces, in the owner's order. It only arranges spaces (on screen and for the
# director); a space keeps its own epics, folder and settings. Deleting a group moves its spaces out of every group.
class SpaceGroup < ApplicationRecord
  UNGROUPED = "Bez grupy"

  belongs_to :user
  has_many :spaces, dependent: :nullify

  normalizes :name, with: ->(value) { value.to_s.squish.presence }
  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :user_id, case_sensitive: false }

  scope :ordered, -> { order(:position, :id) }

  before_create { self.position = (user.space_groups.maximum(:position) || 0) + 1 unless position.to_i.positive? }

  # R2: the owner's groups in the given order (ids of other users' groups are ignored).
  def self.arrange!(user, ids)
    transaction do
      groups = user.space_groups.to_a.index_by(&:id)
      ordered = ids.map(&:to_i).uniq.filter_map { |id| groups.delete(id) } + groups.values.sort_by { |g| [ g.position, g.id ] }
      ordered.each_with_index { |group, i| group.update!(position: i + 1) unless group.position == i + 1 }
    end
  end

  # Spec 051, G4: [[group or nil, spaces]] in the owner's order — the groups, then "Bez grupy" (nil); archived spaces
  # last within their group. Empty groups are kept (so a space can be dragged into them).
  def self.layout(user, spaces)
    by_group = spaces.group_by(&:space_group_id)
    sort = ->(list) { list.sort_by { |s| [ s.active? ? 0 : 1, s.position, s.name.downcase ] } }
    user.space_groups.ordered.map { |g| [ g, sort.(by_group[g.id] || []) ] } + [ [ nil, sort.(by_group[nil] || []) ] ]
  end
end
