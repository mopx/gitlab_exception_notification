## Gitlab Exception Notification

[![Gem Version](https://badge.fury.io/rb/gitlab_exception_notification.svg)](https://badge.fury.io/rb/gitlab_exception_notification)

-----------------

Automatically create, open and updates Gitlab issues on rails exceptions.

Works with the [ExceptionNotification](https://github.com/smartinez87/exception_notification) gem.

#### Setup

Require the gem in your rails project's Gemfile:

```
gem "gitlab_exception_notification"
```

Add the `gitlab` notifier in the [ExceptionNotification](https://github.com/smartinez87/exception_notification) configuration, usually in the `production.rb` file.

```
config.middleware.use ExceptionNotification::Rack,
  :gitlab => {
    private_token: "YOUR_PRIVATE_GITLAB_TOKEN",
    gitlab_url: "YOUR_PRIVATE_GITLAB_ENDPOINT",
    project_name: "YOUR_GITLAB_PROJECT_NAME"
  }
```
