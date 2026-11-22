# Spec 044, G4: the acceptance run of a director on a local model. Eight Polish requests go through the real director
# code (ManagementRunner) to a real local server; each is checked against what it should change. Runs on demand,
# only on throwaway data (R4): the database must be a demo file.
#   DATABASE_URL=sqlite3:storage/demo.sqlite3 AUDIT_DATABASE_URL=sqlite3:storage/demo_audit.sqlite3 \
#     bin/rails agentaro:director:local_check MODEL=mimo-v2.6
#   llama.cpp: … PRESET=openai_compatible_api URL=http://localhost:8080/v1 MODEL=<any name>
module Agentaro
  class DirectorLocalCheck
    Result = Data.define(:request, :ok, :seconds, :calls, :note)

    def self.demo_database?
      path = ActiveRecord::Base.connection_db_config.database.to_s
      File.basename(path).start_with?("demo")
    end

    # preset: "ollama_api" (default) or "openai_compatible_api" (e.g. llama.cpp's llama-server on :8080/v1).
    def initialize(model:, base_url: "http://localhost:11434", preset: "ollama_api", out: $stdout)
      @model, @base_url, @preset, @out = model, base_url, preset, out
    end

    def run
      raise "R4: run it only on the demo database files (DATABASE_URL=sqlite3:storage/demo.sqlite3)" unless self.class.demo_database?

      setup!
      results = requests.map { |text, check| ask(text, check) }
      first = results.count { |r| r.ok && r.calls <= 2 }
      @out.puts "\n#{results.count(&:ok)}/#{results.size} passed (#{first} on the first answer), model #{@model}, " \
                "slowest #{results.map(&:seconds).max.round} s"
      results
    end

    private

    def setup!
      @user = User.create!(username: "localcheck#{Time.current.to_i}", role: "user", password: SecureRandom.hex(16) + "Aa1!", otp_required: false)
      @executor = Executor.find_or_create_by!(name: "Local check (#{@preset})") { |e| e.preset = @preset; e.base_url = @base_url }
      @executor.update!(default_model: @model, enabled: true, base_url: @base_url)
      director = Agent.create!(user: @user, name: "Dyrektor", executor: @executor,
                               master_prompt: "Jesteś dyrektorem zespołu agentów. Prowadzisz listę prac właściciela i planujesz je dla zespołu.")
      member = Agent.create!(user: @user, name: "Wykonawca", executor: @executor, master_prompt: "Wykonujesz zadania rzetelnie.")
      @user.team_roles.create!(agent: director, role: "director")
      @user.team_roles.create!(agent: member, role: "member", role_text: "wykonawca: zakupy, research, pisanie")
      @user.spaces.create!(kind: "project", name: "Dom", goal: "Ogarnięty dom i zakupy", description: "Sprawy domowe")
    end

    def shopping = @user.work_items.where("title LIKE ? OR title LIKE ?", "%akup%", "%ist%").order(:id).first

    def requests
      [
        [ "Dodaj epik: lista zakupów na weekend, w przestrzeni Dom.", -> { shopping.present? } ],
        [ "Zaplanuj kroki dla epiku z listą zakupów.", -> { shopping&.active_steps&.any? && @user.work_items.count == 1 } ], # no steps added as new epics
        [ "Co się teraz dzieje?", -> { @user.chat_messages.where(author: "director").last&.content.present? && @user.chat_messages.where(author: "director").last.actions_summary.to_s.match?(/\A(No changes|)\z/) } ],
        [ "Od teraz pracuj w tempie turbo.", -> { @user.reload.work_tempo == WorkTempo::TURBO || @user.spaces.where(work_tempo: WorkTempo::TURBO).exists? } ],
        [ "Zapamiętaj, że wolę krótkie odpowiedzi.", -> { MemoryFact.where(user: @user).exists? } ],
        [ "Dodaj przestrzeń zespołową Ogród, która dba o warzywnik.", -> { @user.spaces.where("name LIKE ?", "%gr%d%").exists? } ],
        [ "Codziennie o 8:00 sprawdzaj prognozę pogody w przestrzeni Ogród.", -> { @user.recurring_orders.exists? } ],
        [ "Anuluj epik z listą zakupów.", -> { @user.work_items.where(state: "cancelled").exists? } ]
      ]
    end

    def ask(text, check)
      @user.chat_messages.create!(author: "user", content: text)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ManagementRunner.chat!(@user)
      calls = 0
      seconds = 0.0
      6.times do
        run = TaskRun.where(user: @user, state: "queued", purpose: %w[chat director]).order(:id).first or break
        ManagementRunner.new(run).perform!
        calls += ModelCall.where(task_run_id: run.id).count if run.purpose == "chat"
      end
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      ok = check.call
      reply = @user.chat_messages.where.not(author: "user").order(:id).last
      note = "#{reply&.author}: #{reply&.content.to_s.tr("\n", " ").truncate(140)}#{" [#{reply.actions_summary.tr("\n", " ").truncate(120)}]" if reply&.actions_summary.present?}"
      @out.puts format("%-4s %5.1f s  %d calls  %s\n           %s", ok ? "ok" : "FAIL", seconds, calls, text, note)
      Result.new(text, ok, seconds, calls, note)
    end
  end
end
