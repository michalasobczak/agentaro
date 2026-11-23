require "digest"
require "shellwords"

# Spec 052: CI of a space — queuing a run (G2), the folder's fingerprint (R2) and the run itself (G3).
module Ci
  STEP_TIMEOUT = 15.minutes
  LOG_LINES = 50
  MAX_OUTPUT = 512 * 1024
  FINGERPRINT_FILES = 5000
  SKIP_DIRS = %w[.git node_modules tmp log dist build .cache vendor].freeze

  # The config of a space with a working folder and a CI section; nil otherwise (a broken file raises Config::Invalid).
  def self.config_for(space)
    return unless space&.working_dir.present? && space.active?

    Config.for(space.working_dir)
  end

  # G2: a CI run for the space, unless one already waits (a running one may have one more after it).
  def self.queue!(space, trigger:, user: space.user)
    config = begin
      config_for(space)
    rescue Config::Invalid => e
      space.update!(ci_state: "error", ci_log: e.message, ci_finished_at: Time.current)
      return
    end
    return unless config&.ci?
    return if space.ci_runs.where(state: "queued").exists?

    run = TaskRun.create!(user: user, space: space, purpose: "ci", trigger: trigger == "manual" ? "manual" : "scheduled",
                          occurrence_start: Time.current, state: "queued", output: nil)
    space.update!(ci_state: "queued") unless space.ci_runs.where(state: "running").exists?
    ActiveRecord.after_all_transactions_commit { Agentaro::TaskScheduler.enqueue(run.id) }
    run
  end

  # G2 (b), R2: after a step, CI when the folder differs from what the last CI saw.
  def self.after_step(space)
    return unless space && config_for(space)&.ci?
    return if fingerprint(space.working_dir, space: space) == space.ci_fingerprint

    queue!(space, trigger: "step")
  rescue Config::Invalid
    nil
  end

  # R2: git's view of the folder when it is a repository (HEAD and the changed files), else sizes and times of files.
  # B20: the folder's .git/config is the agents' to change (core.fsmonitor, hooks run commands), so git runs in the
  # space's sandbox with those switched off.
  GIT_SAFE = [ "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "core.untrackedCache=false" ].freeze

  def self.fingerprint(dir, space: nil)
    if space && File.directory?(File.join(dir, ".git")) && (git = ExecutorCheck.locate("git")) && Sandbox.available?
      git_line = ->(*args) { Shellwords.join([ git, *GIT_SAFE, "-C", dir, *args ]) }
      head = HostProcess.run(Sandbox::PROGRAM, Sandbox.command(space, git_line.("rev-parse", "HEAD")), chdir: dir, timeout: 10, max_output: 4096)
      status = HostProcess.run(Sandbox::PROGRAM, Sandbox.command(space, git_line.("status", "--porcelain", "--untracked-files=all")), chdir: dir, timeout: 20, max_output: 2 * 1024 * 1024)
      return Digest::SHA256.hexdigest("#{head.stdout}\n#{status.stdout}") if status.success?
    end
    files = []
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir) do |rel|
      next if rel.split("/").any? { |part| SKIP_DIRS.include?(part) }

      path = File.join(dir, rel)
      next unless File.file?(path)

      files << "#{rel}:#{File.size(path)}:#{File.mtime(path).to_f}"
      break if files.size >= FINGERPRINT_FILES
    end
    Digest::SHA256.hexdigest(files.sort.join("\n"))
  rescue SystemCallError
    nil
  end
end
