# Owner fix after spec 018 ("daj dynamiczny podgląd ścieżek podczas pisania… nie znam dokładnej nazwy katalogu"):
# folder names under what the user has typed, for the working-folder field. Only folder names, never files or
# their contents; nothing inside Agentaro's storage and runs, nor inside other users' space folders (spec 018, G4).
class FolderSuggestions
  LIMIT = 30

  Result = Data.define(:exists, :folders)

  def self.for(input, user)
    new(input, user).result
  end

  def initialize(input, user)
    @input = input.to_s.strip
    @user = user
  end

  def result
    path = expand(@input.presence || "~/")
    return Result.new(exists: false, folders: []) unless path&.start_with?("/")

    parent, prefix = path.end_with?("/") ? [ path, "" ] : [ File.dirname(path), File.basename(path) ]
    Result.new(exists: File.directory?(path) && !hidden?(path), folders: list(parent, prefix))
  end

  private

  def expand(text)
    text.start_with?("~") ? text.sub(/\A~/, Dir.home) : text
  rescue ArgumentError
    nil
  end

  def list(parent, prefix)
    return [] unless File.directory?(parent)

    real = File.realpath(parent)
    return [] if hidden?(real)

    names = Dir.children(real).select do |name|
      next false if name.start_with?(".") && !prefix.start_with?(".")
      next false unless name.downcase.start_with?(prefix.downcase)

      full = File.join(real, name)
      File.directory?(full) && !hidden?(full)
    end
    names.sort_by(&:downcase).first(LIMIT).map { |name| File.join(real == "/" ? "" : real, name) + "/" }
  rescue SystemCallError
    [] # no permission, gone meanwhile
  end

  # Folders whose contents are never listed: Agentaro's own, and other users' space folders.
  def hidden?(path)
    blocked = Space.protected_dirs + Space.where.not(working_dir: nil).where.not(user_id: @user.id).distinct.pluck(:working_dir)
    real = File.exist?(path) ? File.realpath(path) : path
    blocked.any? { |dir| real == dir || real.start_with?("#{dir}/") }
  rescue SystemCallError
    true
  end
end
