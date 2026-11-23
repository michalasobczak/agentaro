# Spec 052, G6, R1: CI commands and servers run in macOS sandbox-exec with the rules of a step in a working folder
# (spec 018): writes only in the folder, the temporary folders and /dev; no reads of Agentaro's storage, the runs of
# steps or other spaces' folders; network (and so the Docker socket) allowed.
module Ci
  module Sandbox
    PROGRAM = "/usr/bin/sandbox-exec"

    def self.available? = File.executable?(PROGRAM)

    # Where servers' logs live (spec 052, G4): unreadable to every sandbox but the one of its own space, since a
    # server's process must be able to read the file its output goes to.
    def self.logs_dir = Rails.root.join("var", "servers", Rails.env).to_s # one folder per environment, like the runs

    def self.profile(space)
      folder = File.realpath(space.working_dir)
      denied = (space.denied_dirs + Space.protected_dirs + [ logs_dir ]).uniq.filter_map { |dir| real(dir) }.reject { |dir| folder.start_with?("#{dir}/") || folder == dir }
      own_logs = real(File.join(logs_dir, space.id.to_s))
      writable = [ folder, real(Dir.tmpdir), "/private/tmp", "/private/var/folders", "/dev" ].compact.uniq
      <<~SBPL
        (version 1)
        (allow default)
        (deny file-write*)
        (allow file-write* #{writable.map { |dir| "(subpath #{quote(dir)})" }.join(" ")})
        #{"(deny file-read* #{denied.map { |dir| "(subpath #{quote(dir)})" }.join(" ")})" if denied.any?}
        (allow file-read* (subpath #{quote(own_logs)}))
      SBPL
    end

    # The arguments for one shell command in the sandbox.
    def self.command(space, line) = [ "-p", profile(space), "/bin/sh", "-c", line ]

    def self.real(dir)
      File.realpath(dir)
    rescue SystemCallError
      File.expand_path(dir)
    end

    # SBPL strings: backslash and quote escaped.
    def self.quote(path) = "\"#{path.gsub("\\", "\\\\\\\\").gsub("\"", "\\\"")}\""
  end
end
