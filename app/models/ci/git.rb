# Owner change to spec 052, G5: what Git says about a space's working folder — whether it is a repository, its branch,
# where its remote is, and whether the worktree is clean or has changes to commit (and commits to push). Read in the
# space's sandbox with fsmonitor and hooks off (spec 052, B20), cached for 30 seconds, never raises.
module Ci
  module Git
    Info = Data.define(:repo, :branch, :remote, :changes, :ahead, :behind, :upstream, :error) do
      def clean? = repo && changes.zero?
    end
    TTL = 30.seconds
    CACHE = {}
    LOCK = Monitor.new

    module_function

    def info(space, now: Time.current)
      dir = space.working_dir.presence or return
      LOCK.synchronize do
        hit = CACHE[space.id]
        return hit[:info] if hit && hit[:dir] == dir && hit[:at] > now - TTL
      end
      found = read(space, dir)
      LOCK.synchronize { CACHE[space.id] = { dir: dir, at: now, info: found } }
      found
    end

    def forget(space) = LOCK.synchronize { CACHE.delete(space.id) }

    def read(space, dir)
      return Info.new(false, nil, nil, 0, 0, 0, nil, nil) unless File.exist?(File.join(dir, ".git"))

      git = ExecutorCheck.locate("git")
      return Info.new(true, nil, nil, 0, 0, 0, nil, "git is not on this computer") unless git && Sandbox.available?

      run = ->(*args) { HostProcess.run(Sandbox::PROGRAM, Sandbox.command(space, Shellwords.join([ git, *Ci::GIT_SAFE, "-C", dir, *args ])), chdir: dir, timeout: 10, max_output: 1024 * 1024) }
      status = run.("status", "--porcelain=v2", "--branch", "--untracked-files=normal")
      return Info.new(true, nil, nil, 0, 0, 0, nil, ExecutorCheck.clean(status.stderr).lines.first.to_s.strip.presence || "git status failed") unless status.success?

      lines = status.stdout.to_s.lines.map(&:chomp)
      branch = lines.find { |l| l.start_with?("# branch.head ") }&.delete_prefix("# branch.head ")
      upstream = lines.find { |l| l.start_with?("# branch.upstream ") }&.delete_prefix("# branch.upstream ")
      ahead, behind = lines.find { |l| l.start_with?("# branch.ab ") }.to_s.scan(/[+-](\d+)/).flatten.map(&:to_i)
      changes = lines.count { |l| !l.start_with?("#") && l.present? }
      remote_name = upstream&.split("/")&.first || "origin"
      remote = run.("remote", "get-url", remote_name)
      remote = run.("remote", "get-url", "origin") unless remote.success?
      Info.new(true, branch, (public_remote(remote.stdout.strip) if remote.success?), changes, ahead.to_i, behind.to_i, upstream, nil)
    rescue StandardError => e
      Info.new(true, nil, nil, 0, 0, 0, nil, e.class.name)
    end

    # Never a login or token: https://user:token@host/x → https://host/x.
    def public_remote(url)
      return if url.blank?

      url.sub(%r{\A(\w[\w+.-]*://)[^/@]+@}, "\\1").truncate(200)
    end
  end
end
