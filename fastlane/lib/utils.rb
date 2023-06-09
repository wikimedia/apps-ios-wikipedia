# Utility functions

require 'git'

# Returns true if the `NO_DEPLOY` env var is set to 1
def deploy_disabled?
  ENV['NO_DEPLOY'] == '1'
end

# Returns true if the `NO_TEST` env var is set to 1
def test_disabled?
  ENV['NO_TEST'] == '1'
end

# Runs goals from the project's Makefile, this requires going up to the project directory.
# :args: Additional arguments to be passed to `make`.
# Returns The result of the `make` command
def make(args)
  # Maybe we should write an "uncrustify" fastlane action?...
  Dir.chdir '..' do
    sh 'make ' + args
  end
end

# Generate a list of commit subjects from `rev` to `HEAD`
# :rev: The git SHA to start the log from, defaults to `ENV[LAST_SUCCESS_REV']`
def generate_git_commit_log(rev=ENV['GIT_PREVIOUS_SUCCESSFUL_COMMIT'] || 'HEAD^^^^^')
  g = Git.open ENV['PWD']
  begin
    change_log = g.log.between(rev).map { |c| "- " + c.message.lines.first.chomp }.join "\n"
    "Commit Log:\n\n#{change_log}\n"
  rescue
    "Unable to parse commit logs"
  end
end

# Memoized version of `generate_git_commit_log` which stores the result in `ENV['GIT_COMMIT_LOG']`.
def git_commit_log
  ENV['GIT_COMMIT_LOG'] || ENV['GIT_COMMIT_LOG'] = generate_git_commit_log
end

# Parses JSON output of `plutil`
def info_plist_to_hash(path)
  require 'json'
  JSON.parse! %x[plutil -convert json -o - #{path}]
end

# Hack to read app version from Info.plist
def get_version_short_string(path)
  plist_hash = info_plist_to_hash path
  plist_hash['CFBundleShortVersionString']
end

# commit version bump, call a block, then push the bump to git
def with_bump(push=false)
  if ENV['BUILD_NUMBER']
    increment_build_number(build_number: ENV['BUILD_NUMBER'].to_i)
  else
    increment_build_number
  end
  commit_version_bump
  plist_version = get_version_short_string File.expand_path(File.join(ENV['PWD'], 'Wikipedia/Wikipedia-Info.plist'))
  # tag must be added after the version bump is committed
  add_git_tag(tag: "#{plist_version}.#{Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::BUILD_NUMBER]}")
  yield if block_given?
  push_to_git_remote if push
end
