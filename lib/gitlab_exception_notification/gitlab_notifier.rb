
require "gitlab"
require 'digest'

REJECT_HEADERS = /HTTP_COOKIE|(rack.*)|(action_dispatch.*)/
SLINE = "
"
STAB = SLINE + "    "

PER_PAGE = 40

module ExceptionNotifier
  class GitlabNotifier
    def initialize(options)
      p "Booting issue notifications"
      @client = Gitlab.client(endpoint: 'http://gitlab.42.fr/api/v3', private_token: options[:private_token])
      @project_id = @client.project_search(options[:project_name]).first.id
      @issues = get_all_issues
    end

    def exception_digest exception
      p "<><><><> [#{exception.to_s}][#{exception.backtrace.first.to_s}]"
      "EXC" + Digest::SHA256.hexdigest(exception.to_s + exception.backtrace.first.split(":in").first.to_s)
    end

    def is_same_exception? issue, exception
      return false unless issue and issue.description
      p "[#{issue.description.split(SLINE).last.strip}] <=> [#{@digest}] : [#{issue.description.split(SLINE).last.strip == @digest}]" if issue.description.split(SLINE).last.strip.first == "E"
      issue.description.split(SLINE).last.strip == @digest
    end

    def issue_exists?(exception)
      @issues = get_all_issues
      rest = @issues.select do |i|
        is_same_exception?(i, exception)
      end
      (rest.count > 0 ? rest.first.id : false)
    end

    def get_all_issues
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

    def increment_title issue
      count = ((issue.title =~ /^\([0-9]+\).*/) == 0 ? issue.title.gsub(/^\(([0-9]*)\)(.*)/,'\1').to_i + 1 : 1)
      p "count == #{count}"
      new_title = ((issue.title =~ /^\([0-9]+\).*/) == 0 ? issue.title.gsub(/^\(([0-9]*)\)(.*)/, '(' + count.to_s + ')\2') : "(#{count.to_s}) #{issue.title}")
      p "new title: #{(issue.title =~ /^\([0-9]+\).*/).to_s} (#{(issue.title =~ /^([0-9]*).*/) == 0})"
      return new_title
    end

    def update_issue(id, exception)
      issue = @client.issue(@project_id, id)
      last = issue.updated_at.to_date
      if last < 1.hour.ago
        begin
          p "Adding counter to issue #{id}"
          @client.edit_issue(@project_id, id, {state_event: "reopen"})
          p "Editing issue with title: #{increment_title(issue)}"
          iss = @client.edit_issue(@project_id, id, {title: increment_title(issue)})
          p "done editing"
        rescue Exception => e
          p "An error occured: #{e.inspect}"
        end
      else
        body = ":fire: This issue occured again #{Time.current}.
        \n#### Summary:\n
        #{issue_summary(exception).map { |k, v|  "- #{k}: #{v}"}.join(SLINE)}
        "
        @client.reopen_issue(@project_id, id)
        @client.create_issue_note @project_id, id, body
      end
    end
      

    # The issue title
    def issue_title exception
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

    def issue_description exception

      # Get a 'mardowned' backtrace
      m_backtrace = "```#{SLINE} #{exception.backtrace.join(SLINE)}#{SLINE}```"

      # Get the concerned file
      file = exception.backtrace.first

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
      description << @digest
      p "Digest: #{description.last}"
      description.join("\n\n")
    end

    def md_hash hash, pre = ""
      hash.map { |k, v|  "#{pre}- **#{k}**: `#{v}`"}.join(SLINE)
    end

    def create_issue(exception)
      @client.create_issue(@project_id, issue_title(exception), {description: issue_description(exception)})
    end

    def exception_notification(env, exception, options={})
      @env        = env
      @exception  = exception
      @options    = options.reverse_merge(env['exception_notifier.options'] || {})
      @kontroller = env['action_controller.instance'] || MissingController.new
      @request    = ActionDispatch::Request.new(env)
      @sections   = @options[:sections]
      @data       = (env['exception_notifier.exception_data'] || {}).merge(options[:data] || {})
      @sections   = @sections + %w(data) unless @data.empty?
      @digest     = exception_digest(exception)

      if issue_id = issue_exists?(exception)
        update_issue(issue_id, exception)
      else
        create_issue(exception)
      end
    end

    def call(exception, options={})
      env = options[:env] || {}
      exception_notification(env, exception, options)
    end
  end
end