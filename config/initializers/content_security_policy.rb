# Content Security Policy (Rondo E14). No external resources. Scripts: first-party files only — no inline
# scripts, no eval, no CDNs (spec 007, Q1: JavaScript allowed for the calendar).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self
    policy.img_src :self, :data
    policy.font_src :self
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end
end
