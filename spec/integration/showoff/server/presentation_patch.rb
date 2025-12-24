require 'showoff/presentation'

# Monkey patch to add title accessor if it doesn't exist
# This is needed for tests that use the health endpoint
unless Showoff::Presentation.method_defined?(:title)
  class Showoff::Presentation
    def title
      @title || 'Test Presentation'
    end
  end
end