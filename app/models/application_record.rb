class ApplicationRecord < ActiveRecord::Base
  include Changelogged # spec 004: every data change is recorded

  primary_abstract_class
end
