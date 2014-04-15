require "logger"
require "net/http"
require "net/https"
require "time"
require "json"
require "uri"

module Proteus
  class Build
    attr_reader :pr

    def initialize(owner, repo, pr = nil, update_changelog: pr.nil?, log: Logger.new(STDOUT))
      @owner = owner
      @repo = repo
      @update_changelog = update_changelog
      @log = log
      @log.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
      @pr = {}

      if pr.nil?
        @pr[:id] = pr_from_git_log
        raise ArgumentError, "No Pull Request number could be found in the last commit. You're probably already run this script for the latest PR. Continuing with rest of build steps." unless @pr[:id] =~ /^\d+$/
        @log.info "Merge to master detected. Using ##{@pr[:id]} for change text"
        @pr[:open?] = false
      else
        @pr[:id] = pr
        raise ArgumentError, "#{@pr[:id]} isn't a valid PR number. Please check your build script." unless @pr[:id] =~ /^\d+$/
        @log.info "Pull request build detected. Using ##{@pr[:id]} for change text"
        @pr[:open?] = true
      end
    end

    def retrieve_info
      # PR info
      @details = retrieve_from_github(URI.parse("https://git.mobcastdev.com/api/v3/repos/%s/%s/pulls/%i" % [@owner, @repo, @pr[:id]]))
      
      @pr[:issue_url] = File.join(@details["_links"]["issue"]["href"], "comments")
      @pr[:body] = @details["body"].gsub(/^(\#{1,2})\ /,"##\\1 ")
      @pr[:timestamp] = Time.parse(@details["created_at"])
      @pr[:title] = @details["title"]
    end

    def comment_only?
      @pr[:open?]
    end

    def validate_repo
      unless banned_files_in_diff.empty?
        error_text = "Please do not include any changes to CHANGELOG.md or VERSION in your pull requests."
        post_to_pull_request(error_text)
        raise error_text
      end

      @version_parts = Gem::Version.new(File.read("VERSION").strip).segments rescue [0,0,0]
    end

    def calculate_new_version
      # Guess level of change from PR description
      case @pr[:body]
      when %r{breaking change}i
        @change_type_text = "Major version change detected."
        @version_parts[0] += 1
        @version_parts[1] = 0
        @version_parts[2] = 0
      when %r{new feature}i
        @change_type_text = "Minor version change detected."
        @version_parts[1] += 1
        @version_parts[2] = 0
      when %r{bug\ ?fix|patch}i
        @change_type_text = "Patch version change detected."
        @version_parts[2] += 1
      else
        error_text = <<-ERROR
The pull request description didn't contain any keywords indicating what kind of change this is. Please include a keyword from this list to allow this pull request to be accepted:

| Change type | Usable keywords                  |
|-------------|----------------------------------|
| Patch       | bug fix, bugfix, bugfixes, patch |
| Minor       | new feature                      |
| Major       | breaking change                  |

![#FAIL](http://media.giphy.com/media/13QiUx90uD86Ji/giphy.gif)
ERROR

        post_to_pull_request(error_text) unless @update_changelog
        raise error_text
      end

      @new_version = @version_parts.join(".")
    end

    def comment_with_bump_type
      post_to_pull_request(@change_type_text)
      @log.info "Commented on pull request to state: #{@change_type_text}"
    end

    def update_changelog
      @log.info "New version number: #{@new_version}"
      @log.info "##teamcity[setParameter name='bbb.version' value='#{@new_version}']"

      begin
        changelog = File.read("CHANGELOG.md")
      rescue Errno::ENOENT
        changelog = "# Change log\n\n"
      end

      log_parts = changelog.split("## ")
      log_parts.insert(1,"#{@new_version} ([##{pr[:id]}](https://git.mobcastdev.com/#{@owner}/#{@repo}/pull/#{@pr[:id]}) #{@pr[:timestamp].strftime("%Y-%m-%d %H:%M:%S")})\n\n#{@pr[:title]}\n\n#{@pr[:body]}\n\n")
      
      open("VERSION","w") do |f|
        f.write @new_version
      end
      open("CHANGELOG.md","w") do |f|
        f.write log_parts.join("## ")
      end
    end

    def commit_changes
      @log.info "Committing VERSION and CHANGELOG.md back to Github, tagging with \"v#{@new_version}\""
      `git add VERSION CHANGELOG.md && git commit -m "Automated post-pull-request changelog and version commit" && git tag v#{@new_version} && git push origin master --tags`
    end

    private

    def post_to_pull_request(text)
      uri = URI.parse(@pr[:issue_url])

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      req = Net::HTTP::Post.new(uri.path)
      req.add_field("Authorization", "token #{ENV['GITHUB_TOKEN']}")
      req.body = { body: text }.to_json
      res = http.start do |http|
        http.request(req)
      end

      unless (res.code.to_i / 100) == 2
        raise "Could not post a comment to pull request #{@owner}/#{@repo}##{@pr[:id]}: #{text}"
      end
    end

    def pr_from_git_log
      `git log -1 --oneline`.scan(/Merge pull request #(\d+) from/).first.first rescue nil
    end

    def banned_files_in_diff
      `git diff origin/master --name-only | grep "^\(CHANGELOG.md\|VERSION\)$"`
    end

    def retrieve_from_github(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      req = Net::HTTP::Get.new(uri.path)
      req.add_field("Authorization", "token #{ENV['GITHUB_TOKEN']}")

      res = http.start do |http|
        http.request(req)
      end

      case res.code
      when "401"
        raise "The GITHUB_TOKEN environment variable does not have access to read pull requests in the #{@owner}/#{@repo} repository"
        exit 401
      when "200"
        return JSON.parse(res.body)
      else
        message = JSON.parse(res.body)["message"] rescue res.body
        raise "Github responded with a #{res.code}: #{message} (#{uri.to_s})"
      end
    end
  end
end
