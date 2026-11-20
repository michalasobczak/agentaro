# Owner fix ("potrzebuję też dark mode"): the user chooses auto, light or dark; saved on the account (all devices).
class Account::ThemesController < ApplicationController
  def update
    current_user.update!(theme: params[:theme]) if User::THEMES.key?(params[:theme])
    redirect_back_or_to root_path
  end
end
