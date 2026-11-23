# Spec 053, G4: before a step runs in a space's working folder that is not inside a Git repository, Agentaro creates
# one there, outside the agent's sandbox (Claude Code's sandbox denies writes in a .git made during the run). Only with
# the owner's "Relaxed sandbox" on. No hooks (empty template, R2), Git's environment cleared (HostProcess keeps only a
# few variables), no Git command runs in a folder that already has a repository. Never raises: a failure is a note.
module WorkingGit
  module_function

  # nil when nothing was done, otherwise one line for the step's prompt.
  def prepare(space, user)
    return unless user&.relaxed_sandbox?

    dir = space&.working_dir.presence or return
    return unless File.directory?(dir) && !File.symlink?(dir)
    return if repository?(dir)

    git = ExecutorCheck.locate("git") or return "Git is not installed on this computer, so the folder has no repository."
    result = HostProcess.run(git, [ "init", "--quiet", "--template=", dir ], chdir: dir, timeout: 20, max_output: 64 * 1024)
    Ci::Git.forget(space)
    return "Agentaro created an empty Git repository in your folder just before this step (no commits yet, no remote)." if result.success? && repository?(dir)

    "Agentaro could not create a Git repository in your folder: #{ExecutorCheck.clean(result.stderr.to_s).lines.first.to_s.strip.presence || "git init failed"}."
  rescue StandardError => e
    Rails.logger.error("[git] init for space #{space&.id} failed: #{e.class}: #{e.message}")
    "Agentaro could not create a Git repository in your folder (#{e.class})."
  end

  # A repository holds the folder when the folder or one above it has .git (a directory or a worktree's file).
  def repository?(dir)
    Pathname.new(dir).expand_path.ascend.any? { |path| File.exist?(path.join(".git")) }
  end
end
