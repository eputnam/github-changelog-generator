# frozen_string_literal: true

describe GitHubChangelogGenerator::Generator do
  def label(name)
    { "name" => name }
  end

  def issue(title, labels)
    { "title" => "issue #{title}", "labels" => labels.map { |l| label(l) } }
  end

  def pr(title, labels)
    { "title" => "pr #{title}", "labels" => labels.map { |l| label(l) } }
  end

  def get_titles(issues)
    issues.map { |issue| issue["title"] }
  end

  def default_sections
    %w[enhancements bugs breaking issues]
  end

  describe "#parse_sections" do
    before :each do
      subject { described_class.new }
    end
    context "valid json" do
      let(:sections_string) { "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}, \"bar\": { \"prefix\": \"barfix\", \"labels\": [\"test3\", \"test4\"]}}" }

      let(:sections_array) do
        [
          GitHubChangelogGenerator::Section.new(name: "foo", prefix: "foofix", labels: %w[test1 test2]),
          GitHubChangelogGenerator::Section.new(name: "bar", prefix: "barfix", labels: %w[test3 test4])
        ]
      end

      it "returns an array with 2 objects" do
        arr = subject.parse_sections(sections_string)
        expect(arr.size).to eq 2
        arr.each { |section| expect(section).to be_an_instance_of GitHubChangelogGenerator::Section }
      end

      it "returns correctly constructed sections" do
        require "json"

        sections_json = JSON.parse(sections_string)
        sections_array.each_index do |i|
          expect(sections_array[i].name).to eq sections_json.first[0]
          expect(sections_array[i].prefix).to eq sections_json.first[1]["prefix"]
          expect(sections_array[i].labels).to eq sections_json.first[1]["labels"]
          expect(sections_array[i].issues).to eq []
          sections_json.shift
        end
      end
    end
    context "hash" do
      let(:sections_hash) do
        {
          enhancements: {
            prefix: "**Enhancements**",
            labels: %w[feature enhancement]
          },
          breaking: {
            prefix: "**Breaking**",
            labels: ["breaking"]
          },
          bugs: {
            prefix: "**Bugs**",
            labels: ["bug"]
          }
        }
      end

      let(:sections_array) do
        [
          GitHubChangelogGenerator::Section.new(name: "enhancements", prefix: "**Enhancements**", labels: %w[feature enhancement]),
          GitHubChangelogGenerator::Section.new(name: "breaking", prefix: "**Breaking**", labels: ["breaking"]),
          GitHubChangelogGenerator::Section.new(name: "bugs", prefix: "**Bugs**", labels: ["bug"])
        ]
      end

      it "returns an array with 3 objects" do
        arr = subject.parse_sections(sections_hash)
        expect(arr.size).to eq 3
        arr.each { |section| expect(section).to be_an_instance_of GitHubChangelogGenerator::Section }
      end

      it "returns correctly constructed sections" do
        sections_array.each_index do |i|
          expect(sections_array[i].name).to eq sections_hash.first[0].to_s
          expect(sections_array[i].prefix).to eq sections_hash.first[1][:prefix]
          expect(sections_array[i].labels).to eq sections_hash.first[1][:labels]
          expect(sections_array[i].issues).to eq []
          sections_hash.shift
        end
      end
    end
  end

  describe "#get_string_for_issue" do
    let(:issue) do
      { "title" => "Bug in code" }
    end

    it "formats an issue according to options" do
      expect do
        described_class.new.get_string_for_issue(issue)
      end.not_to raise_error
    end
  end

  describe "#parse_by_sections" do
    context "default sections" do
      let(:options) do
        {
          bug_labels: ["bug"],
          enhancement_labels: ["enhancement"],
          breaking_labels: ["breaking"]
        }
      end

      let(:issues) do
        [
          issue("no labels", []),
          issue("enhancement", ["enhancement"]),
          issue("bug", ["bug"]),
          issue("breaking", ["breaking"]),
          issue("all the labels", %w[enhancement bug breaking])
        ]
      end

      let(:pull_requests) do
        [
          pr("no labels", []),
          pr("enhancement", ["enhancement"]),
          pr("bug", ["bug"]),
          pr("breaking", ["breaking"]),
          pr("all the labels", %w[enhancement bug breaking])
        ]
      end

      subject { described_class.new(options) }

      before :each do
        subject.set_sections_and_maps
        @arr = subject.parse_by_sections(issues, pull_requests)
      end

      it "returns 4 sections" do
        expect(@arr.size).to eq 4
      end

      it "returns default sections" do
        default_sections.each { |default_section| expect(@arr.select { |section| section.name == default_section }.size).to eq 1 }
      end

      it "assigns issues to the correct sections" do
        breaking_section = @arr.select { |section| section.name == "breaking" }[0]
        enhancement_section = @arr.select { |section| section.name == "enhancements" }[0]
        issue_section = @arr.select { |section| section.name == "issues" }[0]
        bug_section = @arr.select { |section| section.name == "bugs" }[0]

        expect(get_titles(breaking_section.issues)).to eq(["issue breaking", "pr breaking"])
        expect(get_titles(enhancement_section.issues)).to eq(["issue enhancement", "issue all the labels", "pr enhancement", "pr all the labels"])
        expect(get_titles(issue_section.issues)).to eq(["issue no labels"])
        expect(get_titles(bug_section.issues)).to eq(["issue bug", "pr bug"])
        expect(get_titles(pull_requests)).to eq(["pr no labels"])
      end
    end
    context "configure sections" do
      let(:options) do
        {
          configure_sections: "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}, \"bar\": { \"prefix\": \"barfix\", \"labels\": [\"test3\", \"test4\"]}}"
        }
      end

      let(:issues) do
        [
          issue("no labels", []),
          issue("test1", ["test1"]),
          issue("test3", ["test3"]),
          issue("test4", ["test4"]),
          issue("all the labels", %w[test1 test2 test3 test4])
        ]
      end

      let(:pull_requests) do
        [
          pr("no labels", []),
          pr("test1", ["test1"]),
          pr("test3", ["test3"]),
          pr("test4", ["test4"]),
          pr("all the labels", %w[test1 test2 test3 test4])
        ]
      end

      subject { described_class.new(options) }

      before :each do
        subject.set_sections_and_maps
        @arr = subject.parse_by_sections(issues, pull_requests)
      end

      it "returns 2 sections" do
        expect(@arr.size).to eq 2
      end

      it "returns only configured sections" do
        expect(@arr.select { |section| section.name == "foo" }.size).to eq 1
        expect(@arr.select { |section| section.name == "bar" }.size).to eq 1
      end

      it "assigns issues to the correct sections" do
        foo_section = @arr.select { |section| section.name == "foo" }[0]
        bar_section = @arr.select { |section| section.name == "bar" }[0]

        expect(get_titles(foo_section.issues)).to eq(["issue test1", "issue all the labels", "pr test1", "pr all the labels"])
        expect(get_titles(bar_section.issues)).to eq(["issue test3", "issue test4", "pr test3", "pr test4"])
        expect(get_titles(pull_requests)).to eq(["pr no labels"])
      end
    end
    context "add sections" do
      let(:options) do
        {
          bug_labels: ["bug"],
          enhancement_labels: ["enhancement"],
          breaking_labels: ["breaking"],
          add_sections: "{ \"foo\": { \"prefix\": \"foofix\", \"labels\": [\"test1\", \"test2\"]}}"
        }
      end

      let(:issues) do
        [
          issue("no labels", []),
          issue("test1", ["test1"]),
          issue("bugaboo", ["bug"]),
          issue("all the labels", %w[test1 test2 enhancement bug])
        ]
      end

      let(:pull_requests) do
        [
          pr("no labels", []),
          pr("test1", ["test1"]),
          pr("enhance", ["enhancement"]),
          pr("all the labels", %w[test1 test2 enhancement bug])
        ]
      end

      subject { described_class.new(options) }

      before :each do
        subject.set_sections_and_maps
        @arr = subject.parse_by_sections(issues, pull_requests)
      end

      it "returns 5 sections" do
        expect(@arr.size).to eq 5
      end

      it "returns default sections" do
        default_sections.each { |default_section| expect(@arr.select { |section| section.name == default_section }.size).to eq 1 }
      end

      it "returns added section" do
        expect(@arr.select { |section| section.name == "foo" }.size).to eq 1
      end

      it "assigns issues to the correct sections" do
        foo_section = @arr.select { |section| section.name == "foo" }[0]
        enhancement_section = @arr.select { |section| section.name == "enhancements" }[0]
        bug_section = @arr.select { |section| section.name == "bugs" }[0]

        expect(get_titles(foo_section.issues)).to eq(["issue test1", "issue all the labels", "pr test1", "pr all the labels"])
        expect(get_titles(enhancement_section.issues)).to eq(["pr enhance"])
        expect(get_titles(bug_section.issues)).to eq(["issue bugaboo"])
        expect(get_titles(pull_requests)).to eq(["pr no labels"])
      end
    end
  end
end
