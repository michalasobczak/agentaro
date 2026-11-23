require "test_helper"

# Owner change to spec 052, G5: the Git state on the space's card — repository or not, branch, remote (never a token),
# changes to commit and commits to push; read in the sandbox.
class SpaceGitTest < ActionDispatch::IntegrationTest
  setup do
    skip "sandbox-exec not on this computer" unless Ci::Sandbox.available?
    @git = ExecutorCheck.locate("git") or skip "git not here"
    @dir = File.realpath(Dir.mktmpdir("git-space"))
    @bare = File.realpath(Dir.mktmpdir("git-remote"))
    @user = create_user
    @space = @user.spaces.create!(kind: "project", name: "Gra", goal: "Gra", working_dir: @dir)
    sign_in(@user)
  end

  teardown do
    [ @dir, @bare ].compact.each { |d| FileUtils.rm_rf(d) }
    Ci::Git.forget(@space) if @space
  end

  def git(*args, dir: @dir) = system(@git, "-C", dir, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(" ")} failed")

  test "a folder without Git says so" do
    assert_equal false, Ci::Git.info(@space).repo
    get spaces_path
    assert_select ".space-git .badge", text: "no Git"
  end

  test "branch, remote without its token, changes to commit and commits to push" do
    git("init", "-q", "--bare", dir: @bare)
    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@example.com")
    git("config", "user.name", "T")
    File.write(File.join(@dir, "a.txt"), "a")
    git("add", ".")
    git("commit", "-q", "-m", "first")
    git("remote", "add", "origin", @bare)
    git("push", "-q", "-u", "origin", "main")
    info = Ci::Git.info(@space)
    assert_equal [ true, "main", 0, 0 ], [ info.repo, info.branch, info.changes, info.ahead ]
    assert info.clean?

    File.write(File.join(@dir, "b.txt"), "b")
    File.write(File.join(@dir, "a.txt"), "changed")
    git("commit", "-q", "-am", "second")
    File.write(File.join(@dir, "a.txt"), "changed again")
    git("remote", "set-url", "origin", "https://owner:ghp_secret123@github.com/owner/repo.git")
    Ci::Git.forget(@space)
    info = Ci::Git.info(@space)
    assert_equal [ 2, 1 ], [ info.changes, info.ahead ]
    assert_equal "https://github.com/owner/repo.git", info.remote

    get spaces_path
    assert_select ".space-git .badge", text: "2 to commit"
    assert_select ".space-git .badge", text: "1 to push"
    assert_select ".space-git", text: /main.*github.com\/owner\/repo/m
    assert_no_match(/ghp_secret123/, response.body)
    get space_path(@space)
    assert_select ".space-folder .space-git"
    assert_select "[style]", 0
  end

  test "B20: the folder's own Git config never runs a command while the card is drawn" do
    git("init", "-q")
    marker = File.join(Dir.home, "agentaro-gitcard-#{SecureRandom.hex(3)}")
    git("config", "core.fsmonitor", "touch #{marker}")
    Ci::Git.info(@space)
    assert_not File.exist?(marker)
  ensure
    FileUtils.rm_f(marker) if marker
  end
end
