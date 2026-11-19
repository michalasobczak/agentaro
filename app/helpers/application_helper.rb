module ApplicationHelper
  # Inline SVG icons (24×24, stroke) — no icon font, no external files (spec 006).
  ICONS = {
    home: '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/><path d="M10 21v-6h4v6"/>',
    sessions: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m10.8 12.2 8.7-8.7M17 6l2.5 2.5M14.5 8.5 17 11"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.3-6 6.5-6s5.9 2.4 6.5 6"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14.3c1.7.8 2.8 2.9 3 5.7"/>',
    log: '<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1"/><circle cx="3.5" cy="12" r="1"/><circle cx="3.5" cy="18" r="1"/>',
    history: '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 7v5l3 2"/>',
    logout: '<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"/><path d="M10 17l5-5-5-5M15 12H3"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    link: '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
    shield: '<path d="M12 3 4.5 6v6c0 4.4 3.2 7.9 7.5 9 4.3-1.1 7.5-4.6 7.5-9V6L12 3Z"/><path d="m9 12 2 2 4-4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    chevron_left: '<path d="m15 6-6 6 6 6"/>',
    chevron_right: '<path d="m9 6 6 6-6 6"/>',
    repeat: '<path d="M17 2l3 3-3 3"/><path d="M4 11V9a4 4 0 0 1 4-4h12"/><path d="M7 22l-3-3 3-3"/><path d="M20 13v2a4 4 0 0 1-4 4H4"/>',
    agent: '<rect x="4" y="7" width="16" height="13" rx="3"/><path d="M12 3v4M9 12h.01M15 12h.01M9.5 16h5M2 12v3M22 12v3"/>',
    chip: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M10 10h4v4h-4zM9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
    pin: '<path d="M12 21s7-6.2 7-11.5A7 7 0 0 0 5 9.5C5 14.8 12 21 12 21Z"/><circle cx="12" cy="9.5" r="2.5"/>'
  }.freeze

  def icon(name, css: "icon")
    tag.svg(ICONS.fetch(name).html_safe, class: css, viewBox: "0 0 24 24", "aria-hidden": "true")
  end

  def nav_link(label, path, icon_name, active: current_page?(path), css: nil)
    link_to path, class: [ ("active" if active), css ].compact.join(" "), "aria-current": (active ? "page" : nil) do
      safe_join([ icon(icon_name), tag.span(label) ])
    end
  end

  def badge(text, kind = nil)
    tag.span(text, class: [ "badge", kind ].compact.join(" "))
  end

  def role_badge(user) = user.admin? ? badge("admin", "accent") : badge("user")

  def account_badge(user)
    return badge("deactivated", "bad") unless user.active?
    return badge("locked", "warn") if user.locked?

    badge("active", "ok")
  end

  def totp_badge(user)
    return badge("off") unless user.otp_required?

    user.otp_enrolled? ? badge("on", "ok") : badge("not set up", "warn")
  end

  def status_class(status) = "status-#{status.to_i / 100}xx"

  def initials(user) = user.username.delete("._-")[0, 2]

  def page_header(title, subtitle = nil, &actions)
    content_for(:title, "#{title} · Agentaro")
    tag.div(class: "page-header") do
      safe_join([
        tag.div { safe_join([ tag.h1(title), (tag.p(subtitle) if subtitle) ].compact) },
        (tag.div(class: "page-actions", &actions) if actions)
      ].compact)
    end
  end

  # Admin tools are for desktop and tablet; phones get this note instead (spec 006, G5).
  def desktop_only_note
    tag.div(class: "callout mobile-note") do
      safe_join([ icon(:info), tag.div { "Admin tools are designed for larger screens. Open this page on a tablet or computer." } ])
    end
  end
end
