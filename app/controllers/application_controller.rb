# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include AuthenticatedSystem

  helper :all # include all helpers, all the time

  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery # :secret => '8a6eeeea65a728190594ee186b4f9258'
  filter_parameter_logging :password, :password_confirmation

  before_filter :seo_filter

protected

  def seo_filter
    @title    = %w(LinuxFr.org)
    @keywords = %w(Linux Logiciel Libre GNU Free Software Actualité Forum Communauté)
    @feeds    = {}
  end

end
