require "gitlab"
require "digest"

module GitlabExceptionNotification

  REJECT_HEADERS = /HTTP_COOKIE|(rack.*)|(action_dispatch.*)/
  SLINE = "\n"
  STAB = SLINE + "    "

  PER_PAGE = 40

  require 'gitlab_exception_notification/issue'
  require 'gitlab_exception_notification/gitlab_notifier'

end
