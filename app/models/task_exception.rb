# Spec 007, R4: one occurrence of a series removed or moved on its own ("this one only").
class TaskException < ApplicationRecord
  belongs_to :task

  validates :occurs_at, presence: true, uniqueness: { scope: :task_id }
end
