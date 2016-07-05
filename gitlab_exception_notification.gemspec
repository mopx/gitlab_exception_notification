$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "gitlab_exception_notification/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "gitlab_exception_notification"
  s.version     = GitlabExceptionNotification::VERSION
  s.authors     = ["Andre Aubin"]
  s.email       = ["andre.aubin@lambdaweb.fr"]
  s.homepage    = "https://github.com/lambda2/gitlab_exception_notification"
  s.summary     = "A Gitlab plugin for the exception_notification gem."
  s.description = "Automatically create, open and updates Gitlab issues on rails exceptions."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_runtime_dependency 'rails', '~> 4.2', '>= 4.2.0'
  s.add_runtime_dependency 'exception_notification', '~> 4.0', '>= 4.0.1'
  s.add_runtime_dependency 'gitlab', '~> 3.5', '>= 3.5.0'

  # s.add_development_dependency "sqlite3"
end
