require "github_changelog_generator/generator/section"

module GitHubChangelogGenerator
  class Entry
    attr_reader :content

    def initialize(options = {})
      @content = ""
      @options = options
    end

    # Generates log entry with header and body
    #
    # @param [Array] pull_requests List or PR's in new section
    # @param [Array] issues List of issues in new section
    # @param [String] newer_tag Name of the newer tag. Could be nil for `Unreleased` section
    # @param [Hash, nil] older_tag Older tag, used for the links. Could be nil for last tag.
    # @return [String] Ready and parsed section
    def create_entry_for_tag(pull_requests, issues, newer_tag, older_tag = nil)
      newer_tag_link, newer_tag_name, newer_tag_time = detect_link_tag_time(newer_tag)

      github_site = @options[:github_site] || "https://github.com"
      project_url = "#{github_site}/#{@options[:user]}/#{@options[:project]}"

      # If the older tag is nil, go back in time from the latest tag and find
      # the SHA for the first commit.
      older_tag_name =
        if older_tag.nil?
          @fetcher.commits_before(newer_tag_time).last["sha"]
        else
          older_tag["name"]
        end

      set_sections_and_maps

      @content = generate_header(newer_tag_name, newer_tag_link, newer_tag_time, older_tag_name, project_url)

      @content += generate_body(pull_requests, issues)

      @content
    end

    # Creates section objects and the label and section maps needed for
    # sorting
    def set_sections_and_maps
      @sections = if configure_sections?
                    parse_sections(@options[:configure_sections])
                  elsif add_sections?
                    default_sections.concat parse_sections(@options[:add_sections])
                  else
                    default_sections
                  end

      @lmap = label_map
      @smap = section_map
    end

    # Creates a hash map of labels => section objects
    #
    # @return [Hash] map of labels => section objects
    def label_map
      label_to_section = {}

      @sections.each do |section_obj|
        section_obj.labels.each do |label|
          label_to_section[label] = section_obj.name
        end
      end

      label_to_section
    end

    # Creates a hash map of 'section name' => section object
    #
    # @return [Hash] map of 'section name' => section object
    def section_map
      map = {}

      @sections.each do |section|
        map[section.name] = section
      end

      map
    end

    # It generate header text for an entry with specific parameters.
    #
    # @param [String] newer_tag_name - name of newer tag
    # @param [String] newer_tag_link - used for links. Could be same as #newer_tag_name or some specific value, like HEAD
    # @param [Time] newer_tag_time - time, when newer tag created
    # @param [String] older_tag_link - tag name, used for links.
    # @param [String] project_url - url for current project.
    # @return [String] - Generate one ready-to-add section.
    def generate_header(newer_tag_name, newer_tag_link, newer_tag_time, older_tag_link, project_url)
      header = ""

      # Generate date string:
      time_string = newer_tag_time.strftime(@options[:date_format])

      # Generate tag name and link
      release_url = if @options[:release_url]
                      format(@options[:release_url], newer_tag_link)
                    else
                      "#{project_url}/tree/#{newer_tag_link}"
                    end
      header += if newer_tag_name.equal?(@options[:unreleased_label])
                  "## [#{newer_tag_name}](#{release_url})\n\n"
                else
                  "## [#{newer_tag_name}](#{release_url}) (#{time_string})\n\n"
                end

      if @options[:compare_link] && older_tag_link
        # Generate compare link
        header += "[Full Changelog](#{project_url}/compare/#{older_tag_link}...#{newer_tag_link})\n\n"
      end

      header
    end

    # Generates complete body text for a tag (without a header)
    #
    # @param [Array] issues
    # @param [Array] pull_requests
    # @returns [String] ready-to-go tag body
    def generate_body(pull_requests, issues)
      body = ""
      body += main_sections_to_log(issues, pull_requests)
      body += merged_section_to_log(pull_requests) if (@options[:pulls] && @options[:add_pr_wo_labels]) || (configure_sections? && @options[:include_merged])
      body
    end

    # Generates main sections for a tag
    #
    # @param [Array] issues
    # @param [Array] pull_requests
    # @return [string] ready-to-go sub-sections
    def main_sections_to_log(issues, pull_requests)
      issues_to_log(issues, pull_requests) if @options[:issues]
    end

    # Generates section for prs with no labels (for a tag)
    #
    # @param [Array] pull_requests
    # @return [string] ready-to-go sub-section
    def merged_section_to_log(pull_requests)
      merged = Section.new(name: "merged", prefix: @options[:merge_prefix], labels: [], issues: pull_requests)
      @sections << merged unless @sections.select { |section| section.name == "merged" }
      generate_sub_section(merged.issues, merged.prefix)
    end

    # Generate ready-to-paste log from list of issues and pull requests.
    #
    # @param [Array] issues
    # @param [Array] pull_requests
    # @return [String] generated log for issues
    def issues_to_log(issues, pull_requests)
      sections_to_log = parse_by_sections(issues, pull_requests)

      log = ""

      sections_to_log.each do |section|
        log += generate_sub_section(section.issues, section.prefix)
      end

      log
    end

    # Boolean method for whether the user is using configure_sections
    def configure_sections?
      !@options[:configure_sections].nil? && !@options[:configure_sections].empty?
    end

    # Boolean method for whether the user is using add_sections
    def add_sections?
      !@options[:add_sections].nil? && !@options[:add_sections].empty?
    end

    # @param [Array] issues List of issues on sub-section
    # @param [String] prefix Name of sub-section
    # @return [String] Generate ready-to-go sub-section
    def generate_sub_section(issues, prefix)
      log = ""

      if issues.any?
        log += "#{prefix}\n\n" unless @options[:simple_list]
        issues.each do |issue|
          merge_string = get_string_for_issue(issue)
          log += "- #{merge_string}\n"
        end
        log += "\n"
      end
      log
    end

    # Turns a string from the commandline into an array of Section objects
    #
    # @param [String, Hash] either string or hash describing sections
    # @return [Array] array of Section objects
    def parse_sections(sections_desc)
      require "json"

      sections_desc = sections_desc.to_json if sections_desc.class == Hash

      begin
        sections_json = JSON.parse(sections_desc)
      rescue JSON::ParserError => e
        raise "There was a problem parsing your JSON string for secions: #{e}"
      end

      sections_arr = []

      sections_json.each do |name, v|
        sections_arr << Section.new(name: name.to_s, prefix: v["prefix"], labels: v["labels"])
      end

      sections_arr
    end

    # This method sort issues by types
    # (bugs, features, or just closed issues) by labels
    #
    # @param [Array] issues
    # @param [Array] pull_requests
    # @return [Hash] Mapping of filtered arrays: (Bugs, Enhancements, Breaking stuff, Issues)
    def parse_by_sections(issues, pull_requests)
      issues.each do |dict|
        added = false

        dict["labels"].each do |label|
          break if @lmap[label["name"]].nil?
          @smap[@lmap[label["name"]]].issues << dict
          added = true

          break if added
        end
        if @smap["issues"]
          @sections.select { |sect| sect.name == "issues" }.last.issues << dict unless added
        end
      end
      sort_pull_requests(pull_requests)
    end

    # Set of default sections for backwards-compatibility/defaults
    #
    # @return [Array] array of Section objects
    def default_sections
      [
        Section.new(name: "breaking", prefix: @options[:breaking_prefix], labels: @options[:breaking_labels]),
        Section.new(name: "enhancements", prefix: @options[:enhancement_prefix], labels: @options[:enhancement_labels]),
        Section.new(name: "bugs", prefix: @options[:bug_prefix], labels: @options[:bug_labels]),
        Section.new(name: "issues", prefix: @options[:issue_prefix], labels: @options[:issue_labels])
      ]
    end

    ENCAPSULATED_CHARACTERS = %w(< > * _ \( \) [ ] #)

    # Encapsulate characters to make Markdown look as expected.
    #
    # @param [String] string
    # @return [String] encapsulated input string
    def encapsulate_string(string)
      string = string.gsub('\\', '\\\\')

      ENCAPSULATED_CHARACTERS.each do |char|
        string = string.gsub(char, "\\#{char}")
      end

      string
    end

    # This method iterates through PRs and sorts them into sections
    #
    # @param [Array] pull_requests
    # @param [Hash] sections
    # @return [Hash] sections
    def sort_pull_requests(pull_requests)
      added_pull_requests = []
      pull_requests.each do |pr|
        added = false

        pr["labels"].each do |label|
          break if @lmap[label["name"]].nil?
          @smap[@lmap[label["name"]]].issues << pr
          added_pull_requests << pr
          added = true

          break if added
        end
      end
      added_pull_requests.each { |p| pull_requests.delete(p) }
      @sections
    end

    # Parse issue and generate single line formatted issue line.
    #
    # Example output:
    # - Add coveralls integration [\#223](https://github.com/skywinder/github-changelog-generator/pull/223) (@skywinder)
    #
    # @param [Hash] issue Fetched issue from GitHub
    # @return [String] Markdown-formatted single issue
    def get_string_for_issue(issue)
      encapsulated_title = encapsulate_string issue["title"]

      title_with_number = "#{encapsulated_title} [\\##{issue['number']}](#{issue['html_url']})"
      if @options[:issue_line_labels].present?
        title_with_number = "#{title_with_number}#{line_labels_for(issue)}"
      end
      issue_line_with_user(title_with_number, issue)
    end

    def line_labels_for(issue)
      labels = if @options[:issue_line_labels] == ["ALL"]
                 issue["labels"]
               else
                 issue["labels"].select { |label| @options[:issue_line_labels].include?(label["name"]) }
               end
      labels.map { |label| " \[[#{label['name']}](#{label['url'].sub('api.github.com/repos', 'github.com')})\]" }.join("")
    end

    def issue_line_with_user(line, issue)
      return line if !@options[:author] || issue["pull_request"].nil?

      user = issue["user"]
      return "#{line} ({Null user})" unless user

      if @options[:usernames_as_github_logins]
        "#{line} (@#{user['login']})"
      else
        "#{line} ([#{user['login']}](#{user['html_url']}))"
      end
    end
  end
end
