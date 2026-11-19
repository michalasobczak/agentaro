# Spec 002, R2: passwords that are too common to accept, even when long enough.
# The list (config/common_passwords.txt) is small and curated; a larger breach list can replace it later.
module CommonPasswords
  def self.include?(password)
    list.include?(password.to_s.downcase)
  end

  def self.list
    @list ||= Rails.root.join("config/common_passwords.txt").readlines(chomp: true)
                   .map { |line| line.strip.downcase }.reject { |line| line.empty? || line.start_with?("#") }.to_set
  end
end
