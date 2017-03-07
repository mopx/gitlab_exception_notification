module GitlabExceptionNotification

  class Issue

    def initialize(env, exception, options={})
      @env        = env
      @exception  = exception
      @options    = options.reverse_merge(env['exception_notifier.options'] || {})
      @kontroller = env['action_controller.instance'] || MissingController.new
      @request    = ActionDispatch::Request.new(env)
      @data       = (env['exception_notifier.exception_data'] || {}).merge(options[:data] || {})
      @digest     = digest
      @client = Gitlab.client(endpoint: options[:gitlab_url], private_token: options[:private_token])
      @project_id = @client.project_search(options[:project_name]).first.id
      @issues     = self.all
    end

    def create
      puts "create_issue with labels: #{[Rails.env, 'bug'].join(',').inspect}"
      @client.create_issue(@project_id, title, {description: description, labels: [Rails.env, 'bug'].join(',')})
    end

    def update(id)
      issue = @client.issue(@project_id, id)
      last = issue.updated_at.to_date
      if last < 1.hour.ago
        begin
          @client.edit_issue(@project_id, id, {state_event: "reopen", labels: [Rails.env, 'bug'].join(',')})
          iss = @client.edit_issue(@project_id, id, {title: increment_title(issue)})
        rescue Exception => e
          p "An error occured: #{e.inspect}"
        end
      else
        body = ":fire: This issue occured again #{Time.current}.
        \n#### Summary:\n
        #{summary.map { |k, v|  "- #{k}: #{v}"}.join(SLINE)}
        "
        @client.reopen_issue(@project_id, id)
        @client.create_issue_note @project_id, id, body
      end
    end

    def is_same_exception? issue
      return false if issue.nil? or issue.description.nil?
      issue.description.split(SLINE).last && issue.description.split(SLINE).last.strip == @digest
    end

    def exists?
      # @issues = self.all
      rest = @issues.select do |i|
        is_same_exception?(i)
      end
      (rest.count > 0 ? rest.first.id : false)
    end

    def all
      page = 1
      i = @client.issues(@project_id, per_page: PER_PAGE, page: page, order_by: :updated_at, labels: [Rails.env, 'bug'].join(','))
      @issues = i
      while i.count == PER_PAGE
        i = @client.issues(@project_id, per_page: PER_PAGE, page: page, order_by: :updated_at, labels: [Rails.env, 'bug'].join(','))
        @issues += i
        page += 1
      end
      return @issues.flatten
    end

    # =====================================================================================
    #                                       Formatters
    # =====================================================================================


    # The issue title
    def title
      t = []
      t << (@exception.message.length > 120 ? @exception.message[0..120] + "..." : @exception.message)
      t.join(' ')
    end

    def summary
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

    def description
      # Get a 'mardowned' backtrace
      m_backtrace = "```#{SLINE} #{@exception.backtrace.join(SLINE)}#{SLINE}```"

      # Get the concerned file
      file = @exception.backtrace.first
      repo_file = file.gsub(/.*\/#{@options[:project_name]}\/([^:]*):(\d*)(:in.*)/, '\1#L\2')

      d = ["> (#{@exception.class}) #{@exception.message} #{@kontroller ? 'in controller ' + @kontroller.controller_name + '#' + @kontroller.action_name : ''}"]

      d << "\n**Full path**: #{file}"
      d << "\n**File**: [#{repo_file}](#{repo_file})"
      {
        'Summary': summary.map { |k, v|  "- #{k}: #{v}"}.join(SLINE),
        'session id': @request.ssl? ? "[FILTERED]" : (@request.session['session_id'] || (@request.env["rack.session.options"] and @request.env["rack.session.options"][:id])).inspect,
        'data': @data,
        'backtrace': m_backtrace,
        'request headers': md_hash(@request.headers),
        'environment': md_hash(@env.reject{|k, v| (REJECT_HEADERS =~ k).nil? })
      }.reject{|k, v| v.nil? or v.blank?}.each do |k, v|
        d << "\n--------------------------------\n"
        d << "#### #{k.to_s.humanize}:\n"
        d << v.to_s
      end
      d << @digest
      d.join(SLINE)
    end

    # =====================================================================================
    #                                       Utilities
    # =====================================================================================

    protected

    def increment_title issue
      count = ((issue.title =~ /^\([0-9]+\).*/) == 0 ? issue.title.gsub(/^\(([0-9]*)\)(.*)/,'\1').to_i + 1 : 1)
      new_title = ((issue.title =~ /^\([0-9]+\).*/) == 0 ? issue.title.gsub(/^\(([0-9]*)\)(.*)/, '(' + count.to_s + ')\2') : "(#{count.to_s}) #{issue.title}")
      return new_title
    end

    def md_hash hash, pre = ""
      hash.map { |k, v|  "#{pre}- **#{k}**: `#{v}`"}.join(SLINE)
    end

    def digest
      puts "Creating digest with: "
      puts "- #{@exception.to_s}"
      puts "- #{@exception.backtrace.first.split(":in").first.to_s}"
      "EXC" + Digest::SHA256.hexdigest(@exception.to_s + @exception.backtrace.first.split(":in").first.to_s)
    end


  end
end
