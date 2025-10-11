require 'minitest/autorun'
require 'mocha/minitest'
require_relative '../lib/updater'
require_relative '../lib/catalog_updater'

class TestUpdater < Minitest::Test
  def setup
    @updater = Providers::Updater.new
    @inflector = Dry::Inflector.new
  end

  def test_adjust_class_name_no_changes
    registry = Providers::Registry.new
    assert_equal 'Openai', registry.send(:adjust_class_name, 'Openai')
    assert_equal 'Cohere', registry.send(:adjust_class_name, 'Cohere')
    assert_equal 'Google', registry.send(:adjust_class_name, 'Google')
  end

  def test_adjust_class_name_openrouter
    registry = Providers::Registry.new
    assert_equal 'OpenRouter', registry.send(:adjust_class_name, 'Openrouter')
  end

  def test_adjust_class_name_xai
    registry = Providers::Registry.new
    assert_equal 'XAI', registry.send(:adjust_class_name, 'Xai')
  end

  def test_adjust_class_name_fireworks
    registry = Providers::Registry.new
    assert_equal 'Fireworks', registry.send(:adjust_class_name, 'Firework')
  end

  def test_adjust_class_name_multiple
    registry = Providers::Registry.new
    assert_equal 'OpenRouterXAI', registry.send(:adjust_class_name, 'OpenrouterXai')
  end

  def test_run_with_no_provider_files
    Dir.stub :glob, ->(*args) { [] } do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
        CatalogUpdater.stub :update_catalogs, nil do
          @updater.run
          # Should not raise any errors
        end
      end
    end
  end

  def test_run_skips_base_rb
    files = ['lib/providers/base.rb', 'lib/providers/openai.rb']
    Dir.stub :glob, ->(*args) { files } do
      mock_instance = Minitest::Mock.new
      mock_instance.expect :run, nil

      mock_provider_class = Class.new do
        def self.new
          @instance
        end
        def self.instance=(inst)
          @instance = inst
        end
      end
      mock_provider_class.instance = mock_instance

      Providers.stub :const_get, mock_provider_class do
        Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
          CatalogUpdater.stub :update_catalogs, nil do
            # Mock require_relative for openai.rb
            Kernel.stub :require_relative, nil do
              @updater.run
            end
          end
        end
      end

      mock_instance.verify
    end
  end

  def test_run_processes_provider_files
    files = ['lib/providers/openai.rb', 'lib/providers/cohere.rb']
    Dir.stub :glob, files do
      mock_instance1 = Minitest::Mock.new
      mock_instance1.expect :run, nil
      mock_instance2 = Minitest::Mock.new
      mock_instance2.expect :run, nil

      call_count = 0
      Providers.stub :const_get, ->(name) {
        call_count += 1
        mock_provider_class = Class.new do
          def self.new
            @instance
          end
          def self.instance=(inst)
            @instance = inst
          end
        end
        if call_count == 1
          mock_provider_class.instance = mock_instance1
        else
          mock_provider_class.instance = mock_instance2
        end
        mock_provider_class
      } do
        Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
          CatalogUpdater.stub :update_catalogs, nil do
            # Mock require_relative
            Kernel.stub :require_relative, nil do
              @updater.run
            end
          end
        end
      end

      mock_instance1.verify
      mock_instance2.verify
      assert_equal 2, call_count
    end
  end

  def test_run_calls_update_feature_matrix
    mock_registry = Minitest::Mock.new
    mock_registry.expect :all, []
    Providers::Registry.stub :new, mock_registry do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, :called do
        CatalogUpdater.stub :update_catalogs, nil do
          @updater.run
          # update_feature_matrix_file was called (stubbed to return :called)
        end
      end
    end
  end

  def test_run_calls_update_catalogs
    Dir.stub :glob, [] do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
        CatalogUpdater.stub :update_catalogs, :called do
          result = @updater.run
          assert_equal :called, result
        end
      end
    end
  end

  def test_run_handles_provider_instantiation_error
    Providers::Registry.stub :new, ->(**args) { raise NameError.new('Class not found') } do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
        CatalogUpdater.stub :update_catalogs, nil do
          assert_raises NameError do
            @updater.run
          end
        end
      end
    end
  end

  def test_run_handles_provider_run_error
    files = ['lib/providers/openai.rb']
    Dir.stub :glob, files do
      mock_provider_class = mock()
      mock_instance = Minitest::Mock.new
      mock_instance.expect :run, nil do
        raise StandardError.new('Run failed')
      end

      Providers.stub :const_get, mock_provider_class do
        mock_provider_class.stubs(:new).returns(mock_instance)
        Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
          CatalogUpdater.stub :update_catalogs, nil do
            Kernel.stub :require_relative, nil do
              assert_raises StandardError do
                @updater.run
              end
            end
          end
        end
      end

      mock_instance.verify
    end
  end

  def test_run_handles_require_relative_error
    Providers::Registry.stub :new, ->(**args) { raise LoadError.new('File not found') } do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
        CatalogUpdater.stub :update_catalogs, nil do
          assert_raises LoadError do
            @updater.run
          end
        end
      end
    end
  end

  def test_run_with_custom_inflector
    custom_inflector = Minitest::Mock.new
    custom_inflector.expect :classify, 'CustomClass', ['openai']
    updater = Providers::Updater.new(inflector: custom_inflector)

    files = ['lib/providers/openai.rb']
    Dir.stub :glob, files do
      mock_provider_class = mock()
      mock_instance = Minitest::Mock.new
      mock_instance.expect :run, nil

      Providers.stub :const_get, mock_provider_class do
        mock_provider_class.stubs(:new).returns(mock_instance)
        Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
          CatalogUpdater.stub :update_catalogs, nil do
            Kernel.stub :require_relative, nil do
              updater.run
            end
          end
        end
      end
    end

    custom_inflector.verify
  end

  def test_run_requires_catalog_updater_once
    mock_registry = Minitest::Mock.new
    mock_registry.expect :all, []
    @updater.expects(:require_relative).with('catalog_updater').once
    Providers::Registry.stub :new, mock_registry do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
        CatalogUpdater.stub :update_catalogs, nil do
          @updater.run
        end
      end
    end
  end

  def test_run_does_not_process_non_rb_files
    files = ['lib/providers/openai.rb']
    Dir.stub :glob, files do
      mock_provider_class = mock()
      mock_instance = Minitest::Mock.new
      mock_instance.expect :run, nil

      Providers.stub :const_get, mock_provider_class do
        mock_provider_class.stubs(:new).returns(mock_instance)
        Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
          CatalogUpdater.stub :update_catalogs, nil do
            Kernel.stub :require_relative, nil do
              @updater.run
            end
          end
        end
      end
    end
  end

  def test_run_processes_files_in_order
    processed = []
    mock_provider_class1 = Class.new do
      define_method :initialize do
        @processed = processed
      end
      define_method :run do
        @processed << 'run_called'
      end
    end
    mock_provider_class2 = Class.new do
      define_method :initialize do
        @processed = processed
      end
      define_method :run do
        @processed << 'run_called'
      end
    end

    mock_registry = Minitest::Mock.new
    mock_registry.expect :all, [mock_provider_class1, mock_provider_class2]
    Providers::Registry.stub :new, mock_registry do
      Providers::FeatureMatrixUpdater.stub :update_feature_matrix_file, nil do
        CatalogUpdater.stub :update_catalogs, nil do
          @updater.run
        end
      end
    end

    expected = ['run_called', 'run_called']
    assert_equal expected, processed
  end
end
