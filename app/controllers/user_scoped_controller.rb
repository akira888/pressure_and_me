class UserScopedController < ApplicationController
  before_action :identify_user
  helper_method :current_user

  private

  def current_user
    @current_user
  end

  def identify_user
    @current_user = User.find_by!(uuid: params[:uuid])
  end
end
