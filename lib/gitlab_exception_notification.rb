module GitlabExceptionNotification

  require "gitlab"
  require 'digest'

  REJECT_HEADERS = /HTTP_COOKIE|(rack.*)|(action_dispatch.*)/
  SLINE = "
  "
  STAB = SLINE + "    "

  PER_PAGE = 40

  require 'gitlab_exception_notification/issue'
  require 'gitlab_exception_notification/gitlab_notifier'

end
