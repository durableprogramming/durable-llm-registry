require 'minitest/autorun'
require 'mocha/minitest'
require_relative '../lib/provider_registry'

class TestProviderRegistry < Minitest::Test
  def test_initialize_loads_providers
    registry = Providers::Registry.new
    assert_instance_of Providers::Registry, registry
    assert registry.all.is_a?(Array)
  end

  def test_all_returns_provider_classes
    registry = Providers::Registry.new
    providers = registry.all
    assert providers.all? { |p| p.is_a?(Class) && p < Providers::Base }
  end

  def test_names_returns_provider_names
    registry = Providers::Registry.new
    names = registry.names
    assert names.is_a?(Array)
    assert names.all? { |n| n.is_a?(String) }
  end

  def test_find_by_name_returns_provider_class
    registry = Providers::Registry.new
    provider = registry.find_by_name('openai')
    assert_equal Providers::Openai, provider
  end

  def test_find_by_name_returns_nil_for_unknown_provider
    registry = Providers::Registry.new
    provider = registry.find_by_name('unknown')
    assert_nil provider
  end

  def test_adjust_class_name_handles_special_cases
    registry = Providers::Registry.new
    assert_equal 'OpenRouter', registry.send(:adjust_class_name, 'Openrouter')
    assert_equal 'XAI', registry.send(:adjust_class_name, 'Xai')
    assert_equal 'Fireworks', registry.send(:adjust_class_name, 'Firework')
    assert_equal 'Openai', registry.send(:adjust_class_name, 'Openai')
  end

  def test_adjust_class_name_no_changes_needed
    registry = Providers::Registry.new
    assert_equal 'Anthropic', registry.send(:adjust_class_name, 'Anthropic')
    assert_equal 'Google', registry.send(:adjust_class_name, 'Google')
  end
end