

module ExceptionNotifier
  class GitlabNotifier
    def initialize(options)
      @options = options
    end


    def exception_notification(env, exception, options={})
      issue = GitlabExceptionNotification::Issue.new(env, exception, options)
      if issue_id = issue.exists?
        issue.update(issue_id)
      else
        issue.create
      end
    end

    def call(exception, options={})
      env = options[:env] || {}
      exception_notification(env, exception, @options.merge(options))
    end
  end
end