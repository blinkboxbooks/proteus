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
      @pr[:merge_to] = @details["base"]["ref"]
    end

    def merge_to_master?
      @pr[:merge_to] == "master"
    end

    def comment_only?
      @pr[:open?]
    end

    def validate_repo
      if comment_only?
        unless banned_files_in_diff.empty?
          error_text = "Please do not include any changes to CHANGELOG.md or VERSION in your pull requests."
          post_to_pull_request(error_text + fail)
          raise error_text
        end
      end

      @version_parts = Gem::Version.new(File.read("VERSION").strip).segments rescue [0,0,0]
    end

    def calculate_new_version
      # Guess level of change from PR description
      # Note that breaking changes do not increment major version in 0.y.z products
      case 
      when @pr[:body] =~ %r{breaking change}i && @version_parts[0] > 0
        @change_type_text = "Major version change detected."
        @version_parts[0] += 1
        @version_parts[1] = 0
        @version_parts[2] = 0
      when @pr[:body] =~ %r{breaking change|new feature}i
        @change_type_text = "Minor version change detected."
        @version_parts[1] += 1
        @version_parts[2] = 0
      when @pr[:body] =~ %r{bug\ ?fix|patch|improvement}i
        @change_type_text = "Patch version change detected."
        @version_parts[2] += 1
      else
        error_text = <<-ERROR
The pull request description didn't contain any keywords indicating what kind of change this is. Please include a keyword from this list to allow this pull request to be accepted:

| Change type | Usable keywords                               |
|-------------|-----------------------------------------------|
| Patch       | bug fix, bugfix, bugfixes, patch, improvement |
| Minor       | new feature                                   |
| Major       | breaking change                               |
ERROR

        post_to_pull_request(error_text + fail) unless @update_changelog
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

    # This assumes you are working against master
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
      # The most recent commit should be the merge between the last pull request commit and the upstream master.
      # We assume that the first parent is the last upstream commit.
      parents = `git log --pretty=%P -1`.split(" ")
      raise "The most recent commit is not a merge, the build process is not behaving as expected" unless parents.length == 2
      last_upstream_commit = parents.first
      files = `git diff #{last_upstream_commit} --name-only`.split("\n")
      banned_files = files.grep(/^(CHANGELOG\.md|VERSION)$/)
      # Allow pull requests that contain *just* CHANGELOG.md and/or VERSION
      return [] if (files - banned_files).empty?
      banned_files
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

    FAIL_GIFS = %w{
      http://media.giphy.com/media/njYrp176NQsHS/giphy.gif
      http://media0.giphy.com/media/aUrv4ohm0IPNS/giphy.gif
      http://media.giphy.com/media/bR4fRofHcFVy8/giphy.gif
      http://media.giphy.com/media/QMJhOD0obsiPe/giphy.gif
      http://media.giphy.com/media/14aUO0Mf7dWDXW/giphy.gif
      http://media.giphy.com/media/rXMkGj2Z3iKGs/giphy.gif
      http://media1.giphy.com/media/YzZ29cRg4hkrK/giphy.gif
      http://media1.giphy.com/media/gLrWjmW6XljZC/giphy.gif
      http://media.giphy.com/media/1014RBn4HVSTK/giphy.gif
    }
    
    def fail
      "\n\n![#FAIL](#{FAIL_GIFS.sample})"
    end
  end
end
