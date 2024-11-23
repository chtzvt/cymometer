# frozen_string_literal: true

require "test_helper"

class TestCymometer < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Cymometer::VERSION
  end
end
