# https://github.com/smartinez87/exception_notification/blob/master/lib/exception_notifier/email_notifier.rb

# module ExceptionNotifier
#   class EmailNotifier < ExceptionNotifier::EmailNotifier.ancestors.second
#     module Mailer
#       class << self
#         alias_method :old_extended, :extended
#       end

#       def self.extended(base)
#         old_extended(base)

#         base.class_eval do
#           def clean_backtrace(exception)
#             exception.backtrace
#           end
#         end
#       end

#     end
#   end
# end

require "gitlab"

REJECT_HEADERS = /HTTP_COOKIE|(rack.*)|(action_dispatch.*)/
SLINE = "
"
STAB = SLINE + "    "

PER_PAGE = 40

module ExceptionNotifier
  class GitlabNotifier
    def initialize(options)
      p "notification with options"
      @client = Gitlab.client(endpoint: 'http://gitlab.42.fr/api/v3', private_token: options[:private_token])
      @project_id = @client.project_search(options[:project_name]).first.id
      @issues = get_all_issues
      # print options.to_yaml
    end

    def issue_exists?(exception)
      p "does issue exists ?"
      @issues = get_all_issues
      p "Having currently #{@issues.length} issues..."
      rest = @issues.select do |i|
        p "- Issue: #{i.title} ( == #{issue_title(exception)} ? -> #{i.title == issue_title(exception)}) && #{i.description && i.description[exception.backtrace.first]}"
        i.title == issue_title(exception) and i.description and i.description[exception.backtrace.first]
      end
      (rest.count > 0 ? rest.first.id : false)
    end

    def get_all_issues
      # return @issues unless @issues.nil?
      page = 1
      i = @client.issues(@project_id, per_page: PER_PAGE, page: page, order_by: :updated_at)
      @issues = i
      while i.count == PER_PAGE
        i = @client.issues(@project_id, per_page: PER_PAGE, page: page, order_by: :updated_at)
        @issues += i
        page += 1
      end
      return @issues.flatten
    end

    def update_issue(id, exception)
      issue = @client.issue(@project_id, id)
      last = issue.updated_at.to_date
      if last < 1.hour.ago
        p "Recent issue !"
        # new_description = issue.description.gsub(/Happened ([0-9]*) times/, "Happened #{$1.to_i + 1} times")
        # p "Ready to update #{issue.id} [#{@project_id}, #{id}, description: #{new_description.length}]"
        
        begin
          @client.edit_issue(@project_id, id, {state_event: "reopen"})
          iss = @client.edit_issue(@project_id, id, {title: "#{issue.title}"})
        rescue Exception => e
          p "ERROOOOOOOOOR"
          p e.inspect
        end
        p "Udated: #{iss.title}"
      else
        body = ":fire: This issue occured again #{Time.current}.
        \n#### Summary:\n
        #{issue_summary(exception).map { |k, v|  "- #{k}: #{v}"}.join(SLINE)}
        "
        @client.reopen_issue(@project_id, id)
        @client.create_issue_note @project_id, id, body
      end
    end

    def issue_title exception
      # The issue title
      title = []
      title << "#{@kontroller.controller_name}##{@kontroller.action_name}" if @kontroller
      title << "(#{exception.class})"
      title << (exception.message.length > 120 ? exception.message[0..120] + "..." : exception.message)
      title.join(' ')
    end

    def issue_summary exception
      {
        'URL': @request.url,
        'HTTP Method': @request.request_method,
        'IP address': @request.remote_ip,
        'Parameters': md_hash(@request.filtered_parameters, STAB),
        'Timestamp': Time.current,
        'Server': Socket.gethostname,
        'Rails root': (defined?(Rails) && Rails.respond_to?(:root) ? Rails.root : nil),
        'Process': $$,
        'session data': md_hash(@request.session.to_hash, STAB),
      }
    end

    def md_hash hash, pre = ""
      hash.map { |k, v|  "#{pre}- **#{k}**: `#{v}`"}.join(SLINE)
    end

    def create_issue(exception)
      file = exception.backtrace.first

      # Get a 'mardowned' backtrace
      m_backtrace = "```#{SLINE} #{exception.backtrace.join(SLINE)}#{SLINE}```"

      # The issue title
      title = issue_title(exception)

      # The issue content
      description = ["#{exception.message} #{@kontroller ? 'in controller ' + @kontroller.controller_name + '#' + @kontroller.action_name : ''}"]
      description << "File: #{file}"
      {
        'Summary': issue_summary(exception).map { |k, v|  "- #{k}: #{v}"}.join(SLINE),
        'session id': @request.ssl? ? "[FILTERED]" : (@request.session['session_id'] || (@request.env["rack.session.options"] and @request.env["rack.session.options"][:id])).inspect,
        'data': @data,
        'backtrace': m_backtrace,
        'request headers': md_hash(@request.headers),
        'environment': md_hash(@env.reject{|k, v| (REJECT_HEADERS =~ k).nil? })
      }.reject{|k, v| v.nil? or v.blank?}.each do |k, v|
        description << "--------------------------------"
        description << "#### #{k.to_s.humanize}: "
        description << v.to_s
      end

      p "creating issue for project [#{@project_id}] with title: #{title}"
      @client.create_issue(@project_id, title, {description: description.join("\n\n")})
    end

    def exception_notification(env, exception, options={})
      p "exception"
      @env        = env
      @exception  = exception
      @options    = options.reverse_merge(env['exception_notifier.options'] || {})
      @kontroller = env['action_controller.instance'] || MissingController.new
      @request    = ActionDispatch::Request.new(env)
      @sections   = @options[:sections]
      @data       = (env['exception_notifier.exception_data'] || {}).merge(options[:data] || {})
      @sections   = @sections + %w(data) unless @data.empty?

      if issue_id = issue_exists?(exception)
        p "Updating issue #{issue_id}..."
        update_issue(issue_id, exception)
      else
        p "Creating issue..."
        create_issue(exception)
      end

      p "end"
            
    end

    def call(exception, options={})
      
      p "Exception called:"
      env = options[:env] || {}
      begin
        exception_notification(env, exception, options)
      rescue Exception => e
        p "YAAAAAAGL"
        p e.inspect
      end
    end
  end
end