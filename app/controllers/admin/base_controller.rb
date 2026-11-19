# Spec 002, G4: admin pages require the admin role (S2: 403 for everyone else).
class Admin::BaseController < ApplicationController
  before_action :require_admin
end
