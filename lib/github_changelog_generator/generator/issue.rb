module GitHubChangelogGenerator
  class Issue
    attr_accessor :name

    def initialize(opts = {})
      @name = opts[:name]
    end
  end
end
