namespace :agentaro do
  namespace :admin do
    desc "Create an admin (asks for password, sets up the authenticator)"
    task :create, [ :username ] => :environment do |_, args|
      require Rails.root.join("lib/agentaro/admin_cli")
      exit(1) unless Agentaro::AdminCli.new.create(args[:username])
    end

    desc "Change an admin's password"
    task :password, [ :username ] => :environment do |_, args|
      require Rails.root.join("lib/agentaro/admin_cli")
      exit(1) unless Agentaro::AdminCli.new.change_password(args[:username])
    end

    desc "Replace an admin's authenticator (TOTP)"
    task :reset_totp, [ :username ] => :environment do |_, args|
      require Rails.root.join("lib/agentaro/admin_cli")
      exit(1) unless Agentaro::AdminCli.new.reset_totp(args[:username])
    end
  end

  namespace :director do
    desc "Spec 044, G4: acceptance run of a director on a local Ollama model (demo database only). MODEL=qwen3.5:9b"
    task local_check: :environment do
      require "agentaro/director_local_check"
      results = Agentaro::DirectorLocalCheck.new(model: ENV.fetch("MODEL", "qwen3.5:9b"), base_url: ENV.fetch("OLLAMA_URL", "http://localhost:11434")).run
      exit 1 unless results.all?(&:ok)
    end
  end

  namespace :brain do
    desc "Spec 031, Q5: read every user's chat history from before the brain, once (in the background)"
    task import_history: :environment do
      User.find_each { |user| puts "#{user.username}: #{Brain::Worker.import_history(user)} messages queued" }
    end
  end

  namespace :traces do
    desc "Spec 030: give runs from before run traces a trace with their joined prompt as one part"
    task backfill: :environment do
      puts "Traces added: #{RunTrace.backfill_legacy!}"
    end
  end

  namespace :audit do
    desc "Verify the hash chains of the audit log and the data changelog"
    task verify: :environment do
      broken = [ AuditEvent, DataChange ].filter_map do |model|
        row = model.first_broken_row
        puts row ? "#{model.name}: BROKEN at row #{row.id} (#{row.occurred_at})" : "#{model.name}: OK (#{model.count} rows)"
        row
      end
      exit(1) if broken.any?
    end

    desc "Remove audit rows older than 3 months (keeps the chains verifiable)"
    task prune: :environment do
      puts "Removed #{Agentaro::AuditRetention.prune!} rows (the running app also does this daily)"
    end
  end
end
