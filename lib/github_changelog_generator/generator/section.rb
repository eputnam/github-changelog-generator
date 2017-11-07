module GitHubChangelogGenerator
  class Section
    attr_accessor :name, :prefix, :issues, :labels

    def initialize(opts = {})
      @name = opts[:name]
      @prefix = opts[:prefix]
      @labels = opts[:labels] || []
      @issues = opts[:issues] || []
    end
  end
end
