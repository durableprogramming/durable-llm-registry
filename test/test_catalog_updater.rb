require 'minitest/autorun'
require 'mocha/minitest'
require 'stringio'
require 'json'
require_relative '../lib/catalog_updater'
require_relative '../lib/colored_logger'

class TestCatalogUpdater < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = ColoredLogger.new(@output)
  end

  def test_update_catalogs_with_valid_data
    mock_dirs = ['catalog/provider1', 'catalog/provider2']
    mock_models_data = [
      { 'name' => 'Model B', 'api_name' => 'model-b' },
      { 'name' => 'Model A', 'api_name' => 'model-a' }
    ]
    mock_rendered_content = '# Catalog for provider1'

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach).yields(JSON.generate(mock_models_data[0])).yields(JSON.generate(mock_models_data[1]))
    Stellar::Erb.stubs(:render).returns(mock_rendered_content)
    File.stubs(:write)
    ColoredLogger.stubs(:new).returns(@logger)

    CatalogUpdater.update_catalogs

    output = @output.string
    assert_match %r{Processing provider: provider1}, output
    assert_match %r{Processing provider: provider2}, output
    assert_match %r{Updated providers.json}, output
  end

  def test_update_catalogs_skips_missing_template
    File.stubs(:exist?).returns(false)
    ColoredLogger.stubs(:new).returns(@logger)

    CatalogUpdater.update_catalogs

    output = @output.string
    # Should log starting but not completion since templates don't exist
    assert_match %r{Starting catalog update process}, output
    refute_match %r{Catalog update process completed}, output
  end

  def test_update_catalogs_handles_no_catalog_dirs
    mock_dirs = []

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    ColoredLogger.stubs(:new).returns(@logger)

    CatalogUpdater.update_catalogs

    output = @output.string
    assert_match %r{Starting catalog update process}, output
    assert_match %r{Updated providers.json}, output
    assert_match %r{Catalog update process completed}, output
  end

  def test_update_catalogs_skips_provider_without_models_file
    mock_dirs = ['catalog/provider1']

    File.stubs(:exist?).returns(true)
    File.stubs(:exist?).with('catalog/provider1/models.jsonl').returns(false)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    ColoredLogger.stubs(:new).returns(@logger)

    CatalogUpdater.update_catalogs

    output = @output.string
    assert_match %r{Processing provider: provider1}, output
    refute_match %r{Loaded .* models for provider1}, output
    refute_match %r{Updated catalog.md for provider1}, output
  end

  def test_update_catalogs_handles_empty_models_file
    mock_dirs = ['catalog/provider1']

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach) # No yields for empty file
    Stellar::Erb.stubs(:render).returns('# Catalog')
    File.stubs(:write)
    ColoredLogger.stubs(:new).returns(@logger)

    CatalogUpdater.update_catalogs

    output = @output.string
    assert_match %r{Loaded 0 models for provider1}, output
  end

  def test_update_catalogs_handles_invalid_json
    mock_dirs = ['catalog/provider1']

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach).yields('invalid json')
    ColoredLogger.stubs(:new).returns(@logger)

    assert_raises JSON::ParserError do
      CatalogUpdater.update_catalogs
    end
  end

  def test_update_catalogs_handles_render_error
    mock_dirs = ['catalog/provider1']
    mock_models_data = [{ 'name' => 'Model A' }]

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach).yields(JSON.generate(mock_models_data[0]))
    ColoredLogger.stubs(:new).returns(@logger)

    assert_raises StandardError do
      CatalogUpdater.update_catalogs
    end
  end

  def test_update_catalogs_handles_write_error
    mock_dirs = ['catalog/provider1']
    mock_models_data = [{ 'name' => 'Model A' }]
    mock_rendered_content = '# Catalog'

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach).yields(JSON.generate(mock_models_data[0]))
    Stellar::Erb.stubs(:render).returns(mock_rendered_content)
    ColoredLogger.stubs(:new).returns(@logger)

    assert_raises StandardError do
      CatalogUpdater.update_catalogs
    end
  end

  def test_update_catalogs_sorts_models_by_name
    mock_dirs = ['catalog/provider1']
    mock_models_data = [
      { 'name' => 'Z Model', 'api_name' => 'z-model' },
      { 'name' => 'A Model', 'api_name' => 'a-model' }
    ]
    expected_sorted = [
      { 'name' => 'A Model', 'api_name' => 'a-model' },
      { 'name' => 'Z Model', 'api_name' => 'z-model' }
    ]

    Stellar::Erb.stubs(:render).returns('# Catalog')
    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach).with(anything).yields(JSON.generate(mock_models_data[0]))
    File.stubs(:write)
    ColoredLogger.stubs(:new).returns(@logger)

    CatalogUpdater.update_catalogs

    output = @output.string
    assert_match %r{Loaded 1 models for provider1}, output
  end

  def test_update_catalogs_handles_file_foreach_error
    mock_dirs = ['catalog/provider1']

    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').returns(mock_dirs)
    File.stubs(:directory?).returns(true)
    File.stubs(:foreach).raises(StandardError.new('File error'))
    ColoredLogger.stubs(:new).returns(@logger)

    assert_raises StandardError do
      CatalogUpdater.update_catalogs
    end
  end

  def test_update_catalogs_handles_dir_glob_error
    File.stubs(:exist?).returns(true)
    Dir.stubs(:glob).with('catalog/*').raises(StandardError.new('Glob error'))
    ColoredLogger.stubs(:new).returns(@logger)

    assert_raises StandardError do
      CatalogUpdater.update_catalogs
    end
  end
end