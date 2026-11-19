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
