# frozen_string_literal: true

require "github_changelog_generator/octo_fetcher"
require "github_changelog_generator/generator/generator_generation"
require "github_changelog_generator/generator/generator_fetcher"
require "github_changelog_generator/generator/generator_processor"
require "github_changelog_generator/generator/generator_tags"
require "github_changelog_generator/generator/section"

module GitHubChangelogGenerator
  # Default error for ChangelogGenerator
  class ChangelogGeneratorError < StandardError
  end

  class Generator
    attr_accessor :options, :filtered_tags, :github, :tag_section_mapping, :sorted_tags, :sections
    attr_reader :lmap, :smap

    # A Generator responsible for all logic, related with change log generation from ready-to-parse issues
    #
    # Example:
    #   generator = GitHubChangelogGenerator::Generator.new
    #   content = generator.compound_changelog
    def initialize(options = {})
      @options        = options
      @tag_times_hash = {}
      @fetcher        = GitHubChangelogGenerator::OctoFetcher.new(options)
      @sections       = []
    end

    def fetch_issues_and_pr
      issues, pull_requests = @fetcher.fetch_closed_issues_and_pr

      @pull_requests = options[:pulls] ? get_filtered_pull_requests(pull_requests) : []

      @issues = options[:issues] ? get_filtered_issues(issues) : []

      fetch_events_for_issues_and_pr
      detect_actual_closed_dates(@issues + @pull_requests)
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

    # Generates log for section with header and body
    #
    # @param [Array] pull_requests List or PR's in new section
    # @param [Array] issues List of issues in new section
    # @param [String] newer_tag Name of the newer tag. Could be nil for `Unreleased` section
    # @param [Hash, nil] older_tag Older tag, used for the links. Could be nil for last tag.
    # @return [String] Ready and parsed section
    def create_log_for_tag(pull_requests, issues, newer_tag, older_tag = nil)
      newer_tag_link, newer_tag_name, newer_tag_time = detect_link_tag_time(newer_tag)

      github_site = options[:github_site] || "https://github.com"
      project_url = "#{github_site}/#{options[:user]}/#{options[:project]}"

      # If the older tag is nil, go back in time from the latest tag and find
      # the SHA for the first commit.
      older_tag_name =
        if older_tag.nil?
          @fetcher.commits_before(newer_tag_time).last["sha"]
        else
          older_tag["name"]
        end

      set_sections_and_maps

      log = ''

      log = generate_header(newer_tag_name, newer_tag_link, newer_tag_time, older_tag_name, project_url)

      log += generate_body(pull_requests, issues)

      log
    end

    # Generates main sections for a tag
    #
    # @param [Array] issues
    # @param [Array] pull_requests
    # @return [string] ready-to-go sub-sections
    def main_sections_to_log(issues, pull_requests)
      issues_to_log(issues, pull_requests) if options[:issues]
    end

    # Generates section for prs with no labels (for a tag)
    #
    # @param [Array] pull_requests
    # @return [string] ready-to-go sub-section
    def merged_section_to_log(pull_requests)
      merged = Section.new(name: "merged", prefix: options[:merge_prefix], labels: [], issues: pull_requests)
      @sections << merged unless @sections.select { |section| section.name == 'merged' }
      generate_sub_section(merged.issues, merged.prefix)
    end

    # Generates complete body section for a tag (without a header)
    #
    # @param [Array] issues
    # @param [Array] pull_requests
    # @returns [String] ready-to-go tag body
    def generate_body(pull_requests,issues)
      body = ''
      body += main_sections_to_log(issues, pull_requests)
      body += merged_section_to_log(pull_requests) if (options[:pulls] && options[:add_pr_wo_labels]) || (configure_sections? && options[:include_merged])
      body
    end

    # Creates section objects and the label and section maps needed for
    # sorting
    def set_sections_and_maps
      @sections = if configure_sections?
                    parse_sections(options[:configure_sections])
                  elsif add_sections?
                    default_sections.concat parse_sections(options[:add_sections])
                  else
                    default_sections
                  end

      @lmap = label_map
      @smap = section_map
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
      !options[:configure_sections].nil? && !options[:configure_sections].empty?
    end

    # Boolean method for whether the user is using add_sections
    def add_sections?
      !options[:add_sections].nil? && !options[:add_sections].empty?
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

    # Set of default sections for backwards-compatibility/defaults
    #
    # @return [Array] array of Section objects
    def default_sections
      [
        Section.new(name: "breaking", prefix: options[:breaking_prefix], labels: options[:breaking_labels]),
        Section.new(name: "enhancements", prefix: options[:enhancement_prefix], labels: options[:enhancement_labels]),
        Section.new(name: "bugs", prefix: options[:bug_prefix], labels: options[:bug_labels]),
        Section.new(name: "issues", prefix: options[:issue_prefix], labels: options[:issue_labels])
      ]
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
  end
end
