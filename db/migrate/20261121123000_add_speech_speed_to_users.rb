# Owner fix after spec 017: how fast Piper speaks, per user (1.5x by default).
class AddSpeechSpeedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :speech_speed, :decimal, precision: 3, scale: 2, null: false, default: 1.5
  end
end
