# Spec 031, G2: which episode a fact came from.
class MemoryFactSource < ApplicationRecord
  belongs_to :memory_fact
  belongs_to :memory_episode
end
